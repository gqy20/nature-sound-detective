from __future__ import annotations

from collections import Counter
import json
from pathlib import Path


def test_challenge_catalog_has_21_unique_target_species() -> None:
    value = json.loads(
        Path("ml/configs/challenge_2026_species.json").read_text(encoding="utf-8")
    )
    classes = value["classes"]
    assert len(classes) == 21
    assert len({row["taxon_id"] for row in classes}) == 21
    assert len({row["name_zh"] for row in classes}) == 21
    assert Counter(row["category_id"] for row in classes) == {
        "bird": 12,
        "insect": 5,
        "frog": 4,
    }


def test_challenge_catalog_records_known_official_label_conflict() -> None:
    value = json.loads(
        Path("ml/configs/challenge_2026_species.json").read_text(encoding="utf-8")
    )
    nightingale = next(row for row in value["classes"] if row["name_zh"] == "普通夜莺")
    assert nightingale["scientific_name"] is None
    assert nightingale["taxonomy_status"] == "conflict_needs_organizer_confirmation"
    assert "普通夜鹰" in nightingale["aliases"]
