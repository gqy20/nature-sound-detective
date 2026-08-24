from __future__ import annotations

import pytest

from app.field_observations import observation_schema, validate_observation_selections
from app.investigation import apply_structured_observations, build_investigation


RESULT = {
    "primary_sound_type": "鸟类鸣叫",
    "detections": [
        {
            "category_id": "bird",
            "name_zh": "鸟类鸣叫",
            "confidence": 0.8,
            "specific_species": {
                "name_zh": "白头鹎",
                "scientific_name": "Pycnonotus sinensis",
            },
        }
    ],
    "card": {"question": "继续观察"},
}


def test_shared_schema_has_story_dimensions():
    schema = observation_schema()
    assert schema["schema_version"] == 1
    assert {item["id"] for item in schema["dimensions"]} == {
        "time", "habitat", "behavior", "sound_pattern", "appearance"
    }


def test_structured_observations_require_two_meaningful_dimensions():
    with pytest.raises(ValueError, match="至少完成两个"):
        validate_observation_selections({"time": ["early_morning"]})
    values = validate_observation_selections(
        {"time": ["early_morning"], "habitat": ["tree_canopy"], "behavior": ["group"]}
    )
    assert [item["label"] for item in values] == ["清晨", "高处树冠", "几只一起活动"]


def test_structured_observations_complete_investigation_for_candidate():
    investigation = build_investigation(RESULT, "杭州", investigation_id="structured")
    updated = apply_structured_observations(
        investigation,
        candidate_id="Pycnonotus sinensis",
        selections={"time": ["early_morning"], "habitat": ["tree_canopy"]},
        observed_at="2026-08-24T00:00:00+00:00",
    )
    assert updated["status"] == "completed"
    assert updated["stop_reason"] == "structured_field_observation_recorded"
    assert [item["label"] for item in updated["observations"]] == ["清晨", "高处树冠"]


def test_structured_observations_reject_wrong_candidate_and_unknown_mixing():
    investigation = build_investigation(RESULT, "杭州")
    with pytest.raises(ValueError, match="候选"):
        apply_structured_observations(
            investigation,
            candidate_id="not-in-result",
            selections={"time": ["early_morning"], "habitat": ["tree_canopy"]},
        )
    with pytest.raises(ValueError, match="无法判断"):
        validate_observation_selections(
            {"behavior": ["unknown", "group"], "time": ["early_morning"]}
        )
