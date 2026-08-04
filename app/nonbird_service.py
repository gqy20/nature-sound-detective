from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

from app.birdnet_service import BirdNetAnalyzer, BirdNetWindows
from app.config import ROOT
from app.observability import get_logger, log_event, log_exception
from ml.nonbird.config import load_nonbird_config
from ml.nonbird.training import sigmoid
from ml.nonbird.rejection import accepted_window_mask


logger = get_logger("nonbird")


class NonBirdAnalyzer:
    def __init__(self, model_dir: Path | None = None) -> None:
        configured = os.getenv("NONBIRD_MODEL_DIR", "").strip()
        self.model_dir = model_dir or (
            Path(configured) if configured else ROOT / "artifacts" / "nonbird" / "model"
        )
        self._classifier = None
        self._metadata: dict[str, Any] | None = None
        self._standalone_birdnet: BirdNetAnalyzer | None = None
        self._lock = threading.Lock()

    @property
    def available(self) -> bool:
        return (self.model_dir / "classifier.h5").is_file() and (
            self.model_dir / "metadata.json"
        ).is_file()

    def _load(self) -> None:
        if self._classifier is not None:
            return
        self._metadata = json.loads(
            (self.model_dir / "metadata.json").read_text(encoding="utf-8")
        )
        self._classifier = tf.keras.models.load_model(
            self.model_dir / "classifier.h5", compile=False
        )

    @property
    def loaded(self) -> bool:
        return self._classifier is not None

    def preload(self) -> dict[str, Any]:
        if not self.available:
            return {"status": "unavailable", "duration_ms": 0}
        started = time.perf_counter()
        with self._lock:
            self._load()
        duration_ms = round((time.perf_counter() - started) * 1000)
        log_event(
            logger,
            logging.INFO,
            "nonbird_model_preload_completed",
            duration_ms=duration_ms,
        )
        return {"status": "ready", "duration_ms": duration_ms}

    def analyze(self, audio_path: Path) -> dict[str, Any]:
        if not self.available:
            return self._unavailable_result()
        if self._standalone_birdnet is None:
            self._standalone_birdnet = BirdNetAnalyzer()
        windows = self._standalone_birdnet.infer_windows(audio_path)
        return self.analyze_windows(windows)

    def analyze_windows(self, windows: BirdNetWindows) -> dict[str, Any]:
        if not self.available:
            return self._unavailable_result()
        if not windows.count:
            return {
                "model": "hangzhou-nonbird-empty-input",
                "scope": "杭州本地蛙类与鸣虫",
                "detections": [],
                "available": True,
            }
        started = time.perf_counter()
        try:
            with self._lock:
                self._load()
                assert self._classifier is not None
                assert self._metadata is not None
                features = windows.embeddings
                probabilities = sigmoid(self._classifier.predict(features, verbose=0))
                metadata = self._metadata
        except Exception:
            log_exception(logger, "nonbird_inference_failed")
            raise

        metadata_classes = metadata.get("classes", [])
        if metadata_classes:
            class_map = {
                str(item["taxon_id"]): item for item in metadata_classes
            }
        else:
            config = load_nonbird_config()
            class_map = {item.taxon_id: item for item in config.classes}
        class_ids = tuple(str(item) for item in metadata["class_ids"])
        thresholds = np.asarray([metadata["thresholds"][item] for item in class_ids])
        accepted = accepted_window_mask(
            features=features,
            probabilities=probabilities,
            groups=np.asarray(["recording"] * windows.count),
            starts=windows.starts,
            ends=windows.ends,
            class_ids=class_ids,
            thresholds=thresholds,
            metadata=metadata,
        )
        detections: list[dict[str, Any]] = []
        for class_index, class_id in enumerate(metadata["class_ids"]):
            if class_id == "background":
                continue
            active = np.flatnonzero(accepted[:, class_index])
            if not len(active):
                continue
            best_index = int(active[np.argmax(probabilities[active, class_index])])
            item = class_map[class_id]
            if isinstance(item, dict):
                category_id = str(item["category_id"])
                taxon_id = str(item["taxon_id"])
                name_zh = str(item["name_zh"])
                scientific_name = item.get("scientific_name")
            else:
                category_id = item.category_id
                taxon_id = item.taxon_id
                name_zh = item.name_zh
                scientific_name = item.scientific_name
            detections.append(
                {
                    "category_id": category_id,
                    "taxon_id": taxon_id,
                    "name_zh": name_zh,
                    "scientific_name": scientific_name,
                    "confidence": round(float(probabilities[best_index, class_index]), 4),
                    "start_seconds": round(float(windows.starts[best_index]), 3),
                    "end_seconds": round(float(windows.ends[best_index]), 3),
                    "status": "likely" if probabilities[best_index, class_index] >= 0.75 else "candidate",
                }
            )
        detections.sort(key=lambda item: item["confidence"], reverse=True)
        log_event(
            logger,
            logging.INFO,
            "nonbird_inference_completed",
            duration_ms=round((time.perf_counter() - started) * 1000),
            detection_count=len(detections),
        )
        return {
            "model": f"{metadata['model_id']} {metadata['version']}",
            "scope": "杭州本地蛙类与鸣虫",
            "detections": detections,
            "available": True,
        }

    @staticmethod
    def _unavailable_result() -> dict[str, Any]:
        return {
            "model": "hangzhou-nonbird-unavailable",
            "scope": "杭州本地蛙类与鸣虫",
            "detections": [],
            "available": False,
        }
