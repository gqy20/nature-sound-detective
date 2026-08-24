from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from app.config import ROOT


SCHEMA_PATH = ROOT / "mobile" / "assets" / "config" / "field_observations.json"


@lru_cache(maxsize=1)
def observation_schema() -> dict[str, Any]:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def validate_observation_selections(
    selections: dict[str, list[str]],
) -> list[dict[str, str]]:
    schema = observation_schema()
    dimensions = {item["id"]: item for item in schema["dimensions"]}
    normalized: list[dict[str, str]] = []
    meaningful_dimensions: set[str] = set()
    for dimension_id, values in selections.items():
        dimension = dimensions.get(dimension_id)
        if dimension is None:
            raise ValueError(f"未知现场观察维度：{dimension_id}")
        if not isinstance(values, list) or not values:
            continue
        if not dimension["multiple"] and len(values) > 1:
            raise ValueError(f"{dimension['label']}只能选择一项")
        options = {item["value"]: item["label"] for item in dimension["options"]}
        if "unknown" in values and len(values) > 1:
            raise ValueError("无法判断不能与其他选项同时选择")
        for value in values:
            if value not in options:
                raise ValueError(f"{dimension['label']}包含无效选项")
            normalized.append(
                {
                    "dimension": dimension_id,
                    "dimension_label": dimension["label"],
                    "value": value,
                    "label": options[value],
                }
            )
            if value != "unknown":
                meaningful_dimensions.add(dimension_id)
    if len(meaningful_dimensions) < int(schema["minimum_meaningful_dimensions"]):
        raise ValueError("请至少完成两个方面的现场观察")
    return normalized
