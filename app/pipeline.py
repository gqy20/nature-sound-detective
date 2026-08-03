from __future__ import annotations

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

from app.birdnet_service import BirdNetAnalyzer
from app.nonbird_service import NonBirdAnalyzer
from app.qwen_service import QwenNatureAnalyzer
from app.result_fusion import fuse_results
from app.observability import get_logger, log_event, log_exception


logger = get_logger("pipeline")


ProgressCallback = Callable[[str, str], None]


class AnalysisPipeline:
    def __init__(
        self,
        *,
        qwen: QwenNatureAnalyzer | None = None,
        birdnet: BirdNetAnalyzer | None = None,
        nonbird: NonBirdAnalyzer | None = None,
    ) -> None:
        self.qwen = qwen
        self.birdnet = birdnet or BirdNetAnalyzer()
        self.nonbird = nonbird or NonBirdAnalyzer()
        self._qwen_lock = threading.Lock()

    def _qwen(self) -> QwenNatureAnalyzer:
        if self.qwen is None:
            with self._qwen_lock:
                if self.qwen is None:
                    self.qwen = QwenNatureAnalyzer()
        return self.qwen

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        # Load sequentially: both TensorFlow-backed models are memory-heavy during
        # initialization, and parallel loading can transiently exhaust RAM.
        components = {
            "birdnet": self.birdnet.preload(),
            "nonbird": self.nonbird.preload(),
        }
        report = {
            "status": "ready",
            "duration_ms": round((time.perf_counter() - started) * 1000),
            "components": components,
        }
        log_event(logger, logging.INFO, "analysis_pipeline_preload_completed", **report)
        return report

    def run(
        self,
        audio_path: Path,
        location: str,
        progress: ProgressCallback,
        *,
        general_audio_path: Path | None = None,
    ) -> dict[str, Any]:
        log_event(logger, logging.INFO, "analysis_pipeline_started")
        progress("analyzing", "正在寻找声音线索")
        with ThreadPoolExecutor(max_workers=3) as executor:
            qwen_future = executor.submit(
                self._qwen().analyze, general_audio_path or audio_path, location
            )
            bird_future = executor.submit(self.birdnet.analyze, audio_path)
            nonbird_future = executor.submit(self.nonbird.analyze, audio_path)
            qwen = qwen_future.result()
            progress("enriching", "正在核对自然知识")
            try:
                birdnet = bird_future.result()
            except Exception as exc:
                log_exception(logger, "birdnet_fallback_used")
                birdnet = {
                    "model": "BirdNET acoustic 2.4",
                    "scope": "杭州MVP六种常见鸟类",
                    "detections": [],
                    "warning": str(exc),
                }
            try:
                nonbird = nonbird_future.result()
            except Exception as exc:
                log_exception(logger, "nonbird_fallback_used")
                nonbird = {
                    "model": "hangzhou-nonbird-unavailable",
                    "scope": "杭州本地蛙类与鸣虫",
                    "detections": [],
                    "available": False,
                    "warning": str(exc),
                }
        progress("composing", "正在生成声音卡")
        result = fuse_results(qwen, birdnet, nonbird)
        log_event(
            logger,
            logging.INFO,
            "analysis_pipeline_completed",
            bird_detection_count=len(birdnet.get("detections", [])),
            nonbird_detection_count=len(nonbird.get("detections", [])),
            sound_type_count=len(result.get("sound_types", [])),
        )
        return result
