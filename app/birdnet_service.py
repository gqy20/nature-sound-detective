from __future__ import annotations

import logging
import threading
import time
from pathlib import Path
from typing import Any

import birdnet

from app.observability import get_logger, log_event, log_exception
from app.species_catalog import birdnet_label_map


logger = get_logger("birdnet")


def _seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


class BirdNetAnalyzer:
    def __init__(self) -> None:
        self._model = None
        self._lock = threading.Lock()

    def _load(self):
        if self._model is None:
            started = time.perf_counter()
            log_event(logger, logging.INFO, "birdnet_model_load_started", model_version="2.4")
            try:
                self._model = birdnet.load("acoustic", "2.4", "tf")
            except Exception:
                log_exception(logger, "birdnet_model_load_failed", model_version="2.4")
                raise
            log_event(
                logger,
                logging.INFO,
                "birdnet_model_load_completed",
                model_version="2.4",
                duration_ms=round((time.perf_counter() - started) * 1000),
            )
        return self._model

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        with self._lock:
            self._load()
        return {
            "status": "ready",
            "duration_ms": round((time.perf_counter() - started) * 1000),
        }

    def analyze(self, audio_path: Path) -> dict[str, Any]:
        started = time.perf_counter()
        species = birdnet_label_map()
        with self._lock:
            model = self._load()
            rows = model.predict(
                [str(audio_path.resolve())],
                custom_species_list=list(species),
                top_k=3,
                default_confidence_threshold=0.05,
                n_producers=1,
                n_workers=1,
                batch_size=4,
                prefetch_ratio=1,
                show_stats="minimal",
            ).to_dataframe().to_dict(orient="records")

        best_by_species: dict[str, dict[str, Any]] = {}
        for row in rows:
            label = str(row["species_name"])
            confidence = float(row["confidence"])
            current = best_by_species.get(label)
            if current is None or confidence > current["confidence"]:
                best_by_species[label] = {
                    "name_zh": species.get(label, label),
                    "label": label,
                    "confidence": round(confidence, 4),
                    "start_seconds": round(_seconds(row["start_time"]), 3),
                    "end_seconds": round(_seconds(row["end_time"]), 3),
                    "status": "likely" if confidence >= 0.5 else "candidate",
                }

        detections = sorted(
            best_by_species.values(), key=lambda item: item["confidence"], reverse=True
        )
        log_event(
            logger,
            logging.INFO,
            "birdnet_inference_completed",
            duration_ms=round((time.perf_counter() - started) * 1000),
            row_count=len(rows),
            detection_count=min(3, len(detections)),
        )
        return {
            "model": "BirdNET acoustic 2.4",
            "scope": f"杭州全年地理先验候选鸟类（{len(species)}种）",
            "detections": detections[:3],
        }
