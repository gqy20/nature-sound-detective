from __future__ import annotations

import math
import struct
import wave

from app.pipeline import AnalysisPipeline
from app.observability import current_trace_id, trace_context
from app.yamnet_service import CATEGORIES, YamNetAnalyzer


def _tone(path, seconds: float = 1.2) -> None:
    sample_rate = 16_000
    frames = bytearray()
    for index in range(round(sample_rate * seconds)):
        value = round(math.sin(2 * math.pi * 440 * index / sample_rate) * 8000)
        frames.extend(struct.pack("<h", value))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(frames)


def test_yamnet_categories_cover_product_soundscape():
    assert {"bird", "frog", "insect", "rain", "running_water", "wind", "speech", "footsteps", "traffic_machine"} <= set(CATEGORIES)


def test_yamnet_runs_locally_and_returns_shared_general_contract(tmp_path):
    audio = tmp_path / "tone.wav"
    _tone(audio)

    result = YamNetAnalyzer().analyze(audio, "杭州")

    assert result["model"] == "YAMNet tflite-1"
    assert result["primary_sound_type"] in result["sound_types"]
    assert result["usage"] is None
    assert "具体物种" in result["uncertainty"]


def test_pipeline_uses_yamnet_and_specialists_in_one_local_flow(tmp_path):
    marker = object()

    class General:
        received = None
        trace_id = None

        def analyze(self, path, location):
            self.received = (path, location)
            self.trace_id = current_trace_id()
            return {
                "model": "yamnet-test",
                "sound_types": ["风和树叶"],
                "primary_sound_type": "风和树叶",
                "confidence_level": "medium",
                "evidence": ["测试证据"],
            }

    class Bird:
        trace_id = None

        def infer_windows(self, _path, progress_callback=None):
            self.trace_id = current_trace_id()
            if progress_callback:
                progress_callback(marker, 1, 1)
            return marker

        def summarize(self, windows):
            assert windows is marker
            return {"model": "bird-test", "scope": "test", "detections": []}

    class NonBird:
        def analyze_windows(self, windows):
            assert windows is marker
            return {"model": "nonbird-test", "detections": [], "available": True}

    general = General()
    pipeline = AnalysisPipeline(general=general, birdnet=Bird(), nonbird=NonBird())
    general_audio = tmp_path / "general.wav"

    with trace_context("trace_test_local_models"):
        result = pipeline.run(
            tmp_path / "bio.wav",
            "杭州",
            lambda *_: None,
            general_audio_path=general_audio,
        )

    assert general.received == (general_audio, "杭州")
    assert result["primary_sound_type"] == "风和树叶"
    assert result["models"]["general_audio"] == "yamnet-test"
    assert result["orchestration"] == "local_models_parallel"
    assert general.trace_id == "trace_test_local_models"
    assert pipeline.birdnet.trace_id == "trace_test_local_models"
