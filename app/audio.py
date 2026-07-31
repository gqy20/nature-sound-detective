from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from app.config import MAX_ANALYSIS_SECONDS


class AudioPreparationError(RuntimeError):
    pass


def prepare_audio(source: Path, destination: Path) -> None:
    """Decode, clip and normalize browser audio for both inference services."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise AudioPreparationError("服务器没有安装 ffmpeg，暂时无法处理录音。")

    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel", "error",
        "-y",
        "-i", str(source),
        "-t", str(MAX_ANALYSIS_SECONDS),
        "-ac", "1",
        "-ar", "16000",
        "-c:a", "pcm_s16le",
        str(destination),
    ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=60)
    if completed.returncode != 0 or not destination.exists():
        detail = completed.stderr.strip()[-500:]
        raise AudioPreparationError(f"录音解码失败：{detail or '无法识别音频格式'}")


def duration_seconds(path: Path) -> float:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return 0.0
    completed = subprocess.run(
        [
            ffprobe, "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", str(path),
        ],
        capture_output=True,
        text=True,
        timeout=15,
    )
    try:
        return round(float(completed.stdout.strip()), 3)
    except ValueError:
        return 0.0
