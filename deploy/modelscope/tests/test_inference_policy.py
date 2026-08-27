import sys
import types
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.modules.setdefault("tensorflow", types.ModuleType("tensorflow"))

from inference import Detection, Interval, StudioAnalyzer, measure_audio_quality  # noqa: E402
from studio_config import BIRD_SPECIES_DISPLAY_THRESHOLD  # noqa: E402


def _bird(score: float) -> Detection:
    return Detection(
        category_id="bird",
        name_zh="鸟类鸣叫",
        confidence=score,
        model="BirdNET",
        intervals=[Interval(0.0, 3.0)],
        species_name="测试鸟",
        scientific_name="Avis test",
    )


def test_species_below_display_threshold_stays_tentative():
    analyzer = StudioAnalyzer()
    result = analyzer._fuse([], [_bird(BIRD_SPECIES_DISPLAY_THRESHOLD - 0.01)], [])

    assert len(result) == 1
    assert result[0].tentative is True


def test_species_at_display_threshold_can_be_specific():
    analyzer = StudioAnalyzer()
    result = analyzer._fuse([], [_bird(BIRD_SPECIES_DISPLAY_THRESHOLD)], [])

    assert len(result) == 1
    assert result[0].tentative is False


def test_detection_key_prefers_scientific_identity():
    detection = _bird(0.8)

    assert detection.key == "bird|Avis test"


def test_clear_audio_is_usable_for_ecology():
    waveform = np.tile(np.array([0.004, -0.004], dtype=np.float32), 24_000)
    quality = measure_audio_quality(waveform, 16_000)

    assert quality.usable is True
    assert quality.weak_signal is False
    assert quality.ecology_usable is True


def test_weak_dynamic_audio_can_be_analyzed_but_not_used_for_ecology():
    waveform = np.zeros(48_000, dtype=np.float32)
    waveform[::100] = 0.021
    quality = measure_audio_quality(waveform, 16_000)

    assert quality.usable is True
    assert quality.weak_signal is True
    assert quality.ecology_usable is False


def test_silence_is_rejected_before_model_inference():
    quality = measure_audio_quality(np.zeros(48_000, dtype=np.float32), 16_000)

    assert quality.usable is False
    assert quality.weak_signal is False
    assert quality.ecology_usable is False
