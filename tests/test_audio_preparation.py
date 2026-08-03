from __future__ import annotations

import shutil
import wave
from pathlib import Path

import pytest

from app.audio import prepare_audio


def _write_silence(path: Path, sample_rate: int = 48_000) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(b"\0\0" * (sample_rate // 10))


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")
def test_prepare_audio_preserves_birdnet_rate_and_creates_general_copy(tmp_path: Path):
    source = tmp_path / "source.wav"
    bioacoustic = tmp_path / "bioacoustic.wav"
    general = tmp_path / "general.wav"
    _write_silence(source)

    prepare_audio(source, bioacoustic, general)

    with wave.open(str(bioacoustic), "rb") as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (48_000, 1, 2)
    with wave.open(str(general), "rb") as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (16_000, 1, 2)
