"""Build the 200-species BirdNET candidate catalog used by the mobile app.

The catalog is selected once, offline, with BirdNET's geographic model at the
Hangzhou city-centre coordinate. The mobile app only ships the resulting JSON;
it does not load the geographic model or require network access at runtime.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import birdnet


LATITUDE = 30.2741
LONGITUDE = 120.1551
CATALOG_SIZE = 200
DEFAULT_NAME_CATALOG = Path("ml/configs/bird_species_zh_cn.json")
RETAINED_SPECIES = {
    "Abroscopus albogularis",
    "Copsychus saularis",
    "Cuculus canorus",
    "Gallinula chloropus",
    "Horornis fortipes",
    "Lanius schach",
    "Passer montanus",
    "Pica serica",
    "Pycnonotus sinensis",
    "Streptopelia chinensis",
    "Turdus mandarinus",
    "Urocissa erythroryncha",
}


def _split_label(label: str) -> tuple[str, str]:
    scientific_name, separator, common_name = label.partition("_")
    if not separator:
        raise ValueError(f"Unexpected BirdNET label: {label!r}")
    return scientific_name, common_name


def load_name_catalog(path: Path = DEFAULT_NAME_CATALOG) -> dict[str, dict[str, object]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    names = document.get("names")
    if not isinstance(names, dict) or not names:
        raise ValueError("简体中文物种名表缺少 names")
    declared_count = document.get("species_count")
    if declared_count is not None and declared_count != len(names):
        raise ValueError("简体中文物种名表数量与条目不一致")
    for scientific_name, row in names.items():
        if not isinstance(scientific_name, str) or not isinstance(row, dict):
            raise ValueError("简体中文物种名表包含无效条目")
        if not isinstance(row.get("name_zh_cn"), str) or not row["name_zh_cn"].strip():
            raise ValueError(f"{scientific_name} 缺少首选简体中文名")
        if not isinstance(row.get("source_name_zh"), str):
            raise ValueError(f"{scientific_name} 缺少 BirdNET 原始中文名")
    return names


def build_catalog(
    name_catalog_path: Path = DEFAULT_NAME_CATALOG,
) -> dict[str, object]:
    preferred_names = load_name_catalog(name_catalog_path)
    geo_model = birdnet.load("geo", "2.4", "tf")
    english_model = birdnet.load("acoustic", "2.4", "tf", lang="en_us")
    chinese_model = birdnet.load("acoustic", "2.4", "tf", lang="zh")

    english_labels = list(english_model.species_list)
    chinese_labels = list(chinese_model.species_list)
    if len(english_labels) != len(chinese_labels):
        raise RuntimeError("BirdNET English and Chinese label counts differ")

    prediction = geo_model.predict(
        LATITUDE,
        LONGITUDE,
        week=None,
        min_confidence=0.0,
    )
    scores = {
        str(name): float(score)
        for name, score in zip(
            prediction.species_list,
            prediction.species_probs,
            strict=True,
        )
    }

    ranked_indices = sorted(
        range(len(english_labels)),
        key=lambda index: scores[english_labels[index]],
        reverse=True,
    )
    selected = ranked_indices[:CATALOG_SIZE]

    index_by_scientific = {
        _split_label(label)[0]: index for index, label in enumerate(english_labels)
    }
    for scientific_name in RETAINED_SPECIES:
        core_index = index_by_scientific[scientific_name]
        if core_index not in selected:
            selected[-1] = core_index

    selected = sorted(
        set(selected),
        key=lambda index: scores[english_labels[index]],
        reverse=True,
    )
    if len(selected) != CATALOG_SIZE:
        raise RuntimeError(f"Expected {CATALOG_SIZE} unique species")

    species = []
    for output_index in selected:
        english_label = english_labels[output_index]
        scientific_name, name_en = _split_label(english_label)
        zh_scientific_name, localized_name = _split_label(
            chinese_labels[output_index]
        )
        if scientific_name != zh_scientific_name:
            raise RuntimeError(f"Label order mismatch at output {output_index}")
        name_entry = preferred_names.get(scientific_name)
        if name_entry is None:
            raise RuntimeError(
                f"Missing Simplified Chinese name for {scientific_name}; "
                "review and update bird_species_zh_cn.json"
            )
        source_name = str(name_entry["source_name_zh"])
        aliases = {str(value) for value in name_entry.get("aliases", [])}
        if localized_name != source_name and localized_name not in aliases:
            raise RuntimeError(
                f"BirdNET Chinese label changed for {scientific_name}: "
                f"{source_name!r} -> {localized_name!r}"
            )
        species.append(
            {
                "output_index": output_index,
                "scientific_name": scientific_name,
                "name_zh": str(name_entry["name_zh_cn"]),
                "source_name_zh": localized_name,
                "name_en": name_en,
                "geo_score": round(scores[english_label], 6),
            }
        )

    return {
        "model": "BirdNET 2.4",
        "selection": "annual geographic prior, with verified and challenge species retained",
        "latitude": LATITUDE,
        "longitude": LONGITUDE,
        "species_count": len(species),
        "species": species,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("mobile/assets/labels/birdnet_hz.json"),
    )
    parser.add_argument(
        "--names",
        type=Path,
        default=DEFAULT_NAME_CATALOG,
        help="Curated Simplified Chinese names keyed by scientific name",
    )
    args = parser.parse_args()
    catalog = build_catalog(args.names)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {catalog['species_count']} species to {args.output}")


if __name__ == "__main__":
    main()
