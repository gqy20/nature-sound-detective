from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from app.config import MAX_ANALYSIS_SECONDS


class AudioPreparationError(RuntimeError):
    pass


def prepare_audio(
    source: Path,
    bioacoustic_destination: Path,
    general_destination: Path | None = None,
) -> None:
    """Create a 48 kHz master and an optional 16 kHz general-audio copy."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise AudioPreparationError("服务器没有安装 ffmpeg，暂时无法处理录音。")

    common = [
        ffmpeg,
        "-hide_banner",
        "-loglevel", "error",
        "-y",
        "-i", str(source),
        "-t", str(MAX_ANALYSIS_SECONDS),
    ]
    command = [
        *common,
        "-ac", "1",
        "-ar", "48000",
        "-c:a", "pcm_s16le",
        str(bioacoustic_destination),
    ]
    if general_destination is not None:
        command.extend([
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            str(general_destination),
        ])
    completed = subprocess.run(command, capture_output=True, text=True, timeout=60)
    expected = [bioacoustic_destination, *([general_destination] if general_destination else [])]
    if completed.returncode != 0 or any(not path.exists() for path in expected):
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
