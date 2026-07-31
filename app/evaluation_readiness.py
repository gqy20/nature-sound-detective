from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from app.evaluation import split_expected


SOUND_TARGETS = {
    "鸟类鸣叫": {"鸟类鸣叫"},
    "蛙类鸣叫": {"蛙类鸣叫"},
    "昆虫鸣叫": {"昆虫鸣叫"},
    "风和树叶": {"风和树叶"},
    "雨水/流水": {"雨水", "流水"},
    "交通或机械噪声": {"交通或机械噪声"},
}


def load_species_targets(path: Path) -> list[str]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return [str(item["name_zh"]) for item in payload.get("birdnet_species", [])]


def readiness_report(
    rows: Iterable[dict[str, Any]], species_targets: Iterable[str],
    sound_minimum: int = 5, species_minimum: int = 10,
) -> dict[str, Any]:
    items = list(rows)

    def counts(predicate: Any) -> dict[str, int]:
        selected = [row for row in items if predicate(row) and row.get("include", "yes") == "yes"]
        verified = sum(row.get("label_status") == "verified" for row in selected)
        weak = sum(row.get("label_status") != "verified" for row in selected)
        return {"verified": verified, "weak": weak, "included": len(selected)}

    sounds: dict[str, dict[str, int]] = {}
    for label, alternatives in SOUND_TARGETS.items():
        bucket = counts(lambda row, allowed=alternatives: bool(
            set(split_expected(str(row.get("expected_sound_types", "")))) & allowed
        ))
        bucket["target"] = sound_minimum
        bucket["gap"] = max(0, sound_minimum - bucket["verified"])
        sounds[label] = bucket

    species: dict[str, dict[str, int]] = {}
    for label in species_targets:
        bucket = counts(lambda row, expected=label: str(row.get("expected_species", "")).strip() == expected)
        bucket["target"] = species_minimum
        bucket["gap"] = max(0, species_minimum - bucket["verified"])
        species[label] = bucket

    sound_ready = all(item["gap"] == 0 for item in sounds.values())
    species_ready = all(item["gap"] == 0 for item in species.values())
    return {
        "manifest_rows": len(items),
        "sound_type_ready": sound_ready,
        "species_ready": species_ready,
        "formal_evaluation_ready": sound_ready and species_ready,
        "sound_types": sounds,
        "species": species,
        "next_action": (
            "可以运行正式评测。" if sound_ready and species_ready
            else "继续人工听音，将 label_status 更新为 verified；弱标签不能计入正式准确率。"
        ),
    }
