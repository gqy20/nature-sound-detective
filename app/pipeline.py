from __future__ import annotations

import logging
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

from app.birdnet_service import BirdNetAnalyzer
from app.nonbird_service import NonBirdAnalyzer
from app.observability import current_trace_id, get_logger, log_event, log_exception, trace_context
from app.result_fusion import fuse_results
from app.yamnet_service import YamNetAnalyzer


logger = get_logger("pipeline")
ProgressCallback = Callable[[str, str, dict[str, Any] | None], None]


class AnalysisPipeline:
    """Local-first analysis shared by API and CLI."""

    def __init__(
        self,
        *,
        general: YamNetAnalyzer | None = None,
        birdnet: BirdNetAnalyzer | None = None,
        nonbird: NonBirdAnalyzer | None = None,
    ) -> None:
        self.general = general or YamNetAnalyzer()
        self.birdnet = birdnet or BirdNetAnalyzer()
        self.nonbird = nonbird or NonBirdAnalyzer()

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        components = {
            "yamnet": self.general.preload(),
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

    def _analyze_bioacoustics(
        self,
        audio_path: Path,
        on_partial: Callable[[dict[str, Any]], None] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        latest: tuple[dict[str, Any], dict[str, Any]] | None = None

        def window_progress(windows, processed: int, total: int) -> None:
            nonlocal latest
            birdnet = self.birdnet.summarize(windows)
            try:
                nonbird = self.nonbird.analyze_windows(windows)
            except Exception as exc:
                log_exception(logger, "nonbird_partial_fallback_used")
                nonbird = self._nonbird_fallback(exc)
            latest = (birdnet, nonbird)
            if on_partial is not None:
                on_partial(
                    {
                        "processed_windows": processed,
                        "total_windows": total,
                        "bird_species": birdnet.get("detections", []),
                        "nonbird_species": nonbird.get("detections", []),
                    }
                )

        windows = self.birdnet.infer_windows(
            audio_path,
            progress_callback=window_progress if on_partial is not None else None,
        )
        if latest is not None:
            return latest
        birdnet = self.birdnet.summarize(windows)
        try:
            nonbird = self.nonbird.analyze_windows(windows)
        except Exception as exc:
            log_exception(logger, "nonbird_fallback_used")
            nonbird = self._nonbird_fallback(exc)
        return birdnet, nonbird

    @staticmethod
    def _nonbird_fallback(exc: Exception) -> dict[str, Any]:
        return {
            "model": "hangzhou-nonbird-unavailable",
            "scope": "杭州本地蛙类与鸣虫",
            "detections": [],
            "available": False,
            "warning": str(exc),
        }

    @staticmethod
    def _general_fallback(exc: Exception) -> dict[str, Any]:
        return {
            "sound_types": ["无法判断"],
            "primary_sound_type": "无法判断",
            "possible_sound_types": [],
            "confidence_level": "low",
            "evidence": [],
            "uncertainty": "通用声景模型暂时不可用，仍可查看专业候选。",
            "model": "YAMNet unavailable",
            "warning": str(exc),
        }

    @staticmethod
    def _bioacoustic_fallback(exc: Exception) -> tuple[dict[str, Any], dict[str, Any]]:
        return (
            {
                "model": "BirdNET acoustic 2.4",
                "scope": "杭州全年地理先验候选鸟类（200种）",
                "detections": [],
                "warning": str(exc),
            },
            {
                "model": "hangzhou-nonbird-unavailable",
                "scope": "杭州本地蛙类与鸣虫",
                "detections": [],
                "available": False,
                "warning": str(exc),
            },
        )

    def run(
        self,
        audio_path: Path,
        location: str,
        progress: ProgressCallback,
        *,
        general_audio_path: Path | None = None,
    ) -> dict[str, Any]:
        log_event(logger, logging.INFO, "analysis_pipeline_started", orchestration="local_models_parallel")
        progress("analyzing", "正在寻找声音线索", None)

        def publish_partial(partial: dict[str, Any]) -> None:
            processed = partial["processed_windows"]
            total = partial["total_windows"]
            progress(
                "analyzing",
                f"已经听完第 {processed}/{total} 段，正在继续核对",
                {
                    "partial_result": partial,
                    "analysis_progress": {
                        "processed_windows": processed,
                        "total_windows": total,
                    },
                },
            )

        trace_id = current_trace_id()

        def run_general() -> dict[str, Any]:
            with trace_context(trace_id):
                return self.general.analyze(general_audio_path or audio_path, location)

        def run_specialists() -> tuple[dict[str, Any], dict[str, Any]]:
            with trace_context(trace_id):
                return self._analyze_bioacoustics(audio_path, publish_partial)

        with ThreadPoolExecutor(max_workers=2) as executor:
            general_future = executor.submit(run_general)
            specialist_future = executor.submit(run_specialists)
            try:
                general = general_future.result()
            except Exception as exc:
                log_exception(logger, "yamnet_fallback_used")
                general = self._general_fallback(exc)
            progress("enriching", "正在核对通用声景与专业候选", None)
            try:
                birdnet, nonbird = specialist_future.result()
            except Exception as exc:
                log_exception(logger, "bioacoustic_fallback_used")
                birdnet, nonbird = self._bioacoustic_fallback(exc)

        progress("composing", "正在生成调查线索", None)
        result = fuse_results(general, birdnet, nonbird)
        result["orchestration"] = "local_models_parallel"
        log_event(
            logger,
            logging.INFO,
            "analysis_pipeline_completed",
            general_detection_count=len(general.get("detections", [])),
            bird_detection_count=len(birdnet.get("detections", [])),
            nonbird_detection_count=len(nonbird.get("detections", [])),
            sound_type_count=len(result.get("sound_types", [])),
            orchestration="local_models_parallel",
        )
        return result
