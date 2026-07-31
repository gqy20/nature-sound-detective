from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable

from app.birdnet_service import BirdNetAnalyzer
from app.qwen_service import QwenNatureAnalyzer
from app.result_fusion import fuse_results


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
    ) -> dict[str, Any]:
        progress("analyzing", "正在寻找声音线索")
        with ThreadPoolExecutor(max_workers=2) as executor:
            qwen_future = executor.submit(self.qwen.analyze, audio_path, location)
            bird_future = executor.submit(self.birdnet.analyze, audio_path)
            qwen = qwen_future.result()
            progress("enriching", "正在核对自然知识")
            try:
                birdnet = bird_future.result()
            except Exception as exc:
                birdnet = {
                    "model": "BirdNET acoustic 2.4",
                    "scope": "杭州MVP六种常见鸟类",
                    "detections": [],
                    "warning": str(exc),
                }
        progress("composing", "正在生成声音卡")
        return fuse_results(qwen, birdnet)
