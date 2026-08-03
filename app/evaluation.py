from __future__ import annotations

from collections import Counter
from typing import Any, Iterable


FREESOUND_SOUND_TYPES = {
    "distant_traffic": ("交通或机械噪声",),
    "people_footsteps": ("脚步",),
    "rain_water_park": ("雨水", "流水"),
    "wind_trees": ("风和树叶",),
}


def split_expected(value: str | None) -> list[str]:
    """Parse pipe-separated acceptable labels while preserving their order."""
    return list(dict.fromkeys(part.strip() for part in (value or "").split("|") if part.strip()))


def score_case(case: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    expected_types = split_expected(str(case.get("expected_sound_types", "")))
    primary = str(result.get("primary_sound_type", ""))
    predicted_types = result.get("detected_sound_types", [])
    if not isinstance(predicted_types, list):
        predicted_types = []
    predicted_types = list(dict.fromkeys([primary, *map(str, predicted_types)]))
    expected_species = str(case.get("expected_species", "")).strip()
    predicted_species: list[str] = []
    for key in ("bird_species", "nonbird_species"):
        rows = result.get(key, [])
        if isinstance(rows, list):
            predicted_species.extend(
                str(item.get("name_zh", "")) for item in rows if isinstance(item, dict)
            )
    detections = result.get("detections", [])
    if isinstance(detections, list):
        for detection in detections:
            species = detection.get("specific_species") if isinstance(detection, dict) else None
            if isinstance(species, dict):
                predicted_species.append(str(species.get("name_zh", "")))
    predicted_species = list(dict.fromkeys(name for name in predicted_species if name))
    return {
        "sound_type_evaluable": bool(expected_types),
        "sound_type_hit": bool(set(expected_types) & set(predicted_types)) if expected_types else None,
        "species_evaluable": bool(expected_species),
        "species_hit": expected_species in predicted_species if expected_species else None,
        "predicted_primary_sound_type": primary,
        "predicted_sound_types": predicted_types,
        "predicted_species": predicted_species,
    }


def summarize(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    items = list(rows)
    successful = [row for row in items if not row.get("error")]
    sound_rows = [row for row in successful if row.get("sound_type_evaluable")]
    species_rows = [row for row in successful if row.get("species_evaluable")]
    verified = [row for row in successful if row.get("label_status") == "verified"]
    sound_confusions = Counter(
        f"{row.get('expected_sound_types', '')} -> {row.get('predicted_primary_sound_type', '')}"
        for row in sound_rows
    )
    species_by_expected: dict[str, dict[str, int]] = {}
    for row in species_rows:
        label = str(row.get("expected_species", ""))
        bucket = species_by_expected.setdefault(label, {"cases": 0, "hits": 0})
        bucket["cases"] += 1
        bucket["hits"] += int(bool(row.get("species_hit")))

    def ratio(rows_: list[dict[str, Any]], key: str) -> float | None:
        return round(sum(bool(row.get(key)) for row in rows_) / len(rows_), 4) if rows_ else None

    return {
        "cases": len(items),
        "successful": len(successful),
        "failed": len(items) - len(successful),
        "verified_cases": len(verified),
        "warning": (
            "当前结果包含弱标签，只能用于探索性诊断，不能作为正式准确率。"
            if len(verified) < len(successful)
            else "全部成功样本均为人工确认标签。"
        ),
        "sound_type_cases": len(sound_rows),
        "sound_type_hit_rate": ratio(sound_rows, "sound_type_hit"),
        "species_cases": len(species_rows),
        "species_candidate_recall": ratio(species_rows, "species_hit"),
        "predicted_sound_type_counts": dict(Counter(row.get("predicted_primary_sound_type", "") for row in successful)),
        "sound_confusions": dict(sound_confusions),
        "species_by_expected": species_by_expected,
        "error_counts": dict(Counter(str(row.get("error", "")) for row in items if row.get("error"))),
    }
