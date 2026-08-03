from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


DEFAULT_CONFIG_PATH = Path(__file__).resolve().parents[1] / "configs" / "hangzhou_nonbird_species.json"


@dataclass(frozen=True)
class NonBirdClass:
    taxon_id: str
    category_id: str
    name_zh: str
    scientific_name: str | None
    default_threshold: float
    status: str


@dataclass(frozen=True)
class NonBirdConfig:
    model_id: str
    version: str
    sample_rate: int
    window_seconds: float
    classes: tuple[NonBirdClass, ...]

    @property
    def class_ids(self) -> tuple[str, ...]:
        return tuple(item.taxon_id for item in self.classes)


@lru_cache(maxsize=4)
def load_nonbird_config(path: Path = DEFAULT_CONFIG_PATH) -> NonBirdConfig:
    value = json.loads(path.read_text(encoding="utf-8"))
    classes = tuple(
        NonBirdClass(
            taxon_id=str(row["taxon_id"]),
            category_id=str(row["category_id"]),
            name_zh=str(row["name_zh"]),
            scientific_name=(
                str(row["scientific_name"]) if row.get("scientific_name") else None
            ),
            default_threshold=float(row["default_threshold"]),
            status=str(row["status"]),
        )
        for row in value["classes"]
    )
    if not classes or len({item.taxon_id for item in classes}) != len(classes):
        raise ValueError("非鸟类别配置必须包含唯一的 taxon_id")
    if any(not 0 < item.default_threshold < 1 for item in classes):
        raise ValueError("非鸟类别阈值必须位于 0 和 1 之间")
    return NonBirdConfig(
        model_id=str(value["model_id"]),
        version=str(value["version"]),
        sample_rate=int(value["sample_rate"]),
        window_seconds=float(value["window_seconds"]),
        classes=classes,
    )
