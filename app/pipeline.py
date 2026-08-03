from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import logging
from pathlib import Path
from typing import Any, Callable

from app.birdnet_service import BirdNetAnalyzer
from app.qwen_service import QwenNatureAnalyzer
from app.result_fusion import fuse_results
from app.observability import get_logger, log_event, log_exception


logger = get_logger("pipeline")


ProgressCallback = Callable[[str, str], None]


class AnalysisPipeline:
    def __init__(self) -> None:
        self.qwen = QwenNatureAnalyzer()
        self.birdnet = BirdNetAnalyzer()

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
        with ThreadPoolExecutor(max_workers=2) as executor:
            qwen_future = executor.submit(
                self.qwen.analyze, general_audio_path or audio_path, location
            )
            bird_future = executor.submit(self.birdnet.analyze, audio_path)
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
        progress("composing", "正在生成声音卡")
        result = fuse_results(qwen, birdnet)
        log_event(
            logger,
            logging.INFO,
            "analysis_pipeline_completed",
            bird_detection_count=len(birdnet.get("detections", [])),
            sound_type_count=len(result.get("sound_types", [])),
        )
        return result
