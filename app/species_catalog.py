from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from app.config import ROOT


BIRDNET_CATALOG_PATH = ROOT / "mobile" / "assets" / "labels" / "birdnet_hz.json"


@dataclass(frozen=True)
class BirdNetSpecies:
    output_index: int
    scientific_name: str
    name_zh: str
    name_en: str
    geo_score: float

    @property
    def birdnet_label(self) -> str:
        return f"{self.scientific_name}_{self.name_en}"


@lru_cache(maxsize=1)
def load_hangzhou_birdnet_catalog(
    path: Path = BIRDNET_CATALOG_PATH,
) -> tuple[BirdNetSpecies, ...]:
    document = json.loads(path.read_text(encoding="utf-8"))
    rows = document.get("species")
    if not isinstance(rows, list) or not rows:
        raise ValueError("杭州 BirdNET 候选目录缺少 species")
    declared_count = document.get("species_count")
    if declared_count is not None and declared_count != len(rows):
        raise ValueError("杭州 BirdNET 候选目录数量与条目不一致")

    species = tuple(
        BirdNetSpecies(
            output_index=int(row["output_index"]),
            scientific_name=str(row["scientific_name"]),
            name_zh=str(row["name_zh"]),
            name_en=str(row["name_en"]),
            geo_score=float(row["geo_score"]),
        )
        for row in rows
    )
    indices = {item.output_index for item in species}
    labels = {item.birdnet_label for item in species}
    if len(indices) != len(species) or len(labels) != len(species):
        raise ValueError("杭州 BirdNET 候选目录包含重复物种")
    if any(item.output_index < 0 or item.output_index >= 6522 for item in species):
        raise ValueError("杭州 BirdNET 候选目录包含无效输出索引")
    return species


def birdnet_label_map() -> dict[str, str]:
    return {item.birdnet_label: item.name_zh for item in load_hangzhou_birdnet_catalog()}
