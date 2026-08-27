import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.modules.setdefault("tensorflow", types.ModuleType("tensorflow"))

from inference import Detection, Interval, StudioAnalyzer  # noqa: E402
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
