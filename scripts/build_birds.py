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
CORE_SPECIES = {
    "Abroscopus albogularis": "棕脸鹟莺",
    "Copsychus saularis": "鹊鸲",
    "Cuculus canorus": "大杜鹃",
    "Gallinula chloropus": "黑水鸡",
    "Horornis fortipes": "强脚树莺",
    "Lanius schach": "棕背伯劳",
    "Passer montanus": "麻雀",
    "Pica serica": "喜鹊",
    "Pycnonotus sinensis": "白头鹎",
    "Streptopelia chinensis": "珠颈斑鸠",
    "Turdus mandarinus": "乌鸫",
    "Urocissa erythroryncha": "红嘴蓝鹊",
}


def _split_label(label: str) -> tuple[str, str]:
    scientific_name, separator, common_name = label.partition("_")
    if not separator:
        raise ValueError(f"Unexpected BirdNET label: {label!r}")
    return scientific_name, common_name


def build_catalog() -> dict[str, object]:
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
    for scientific_name in CORE_SPECIES:
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
        name_zh = CORE_SPECIES.get(scientific_name, localized_name)
        species.append(
            {
                "output_index": output_index,
                "scientific_name": scientific_name,
                "name_zh": name_zh,
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
    args = parser.parse_args()
    catalog = build_catalog()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {catalog['species_count']} species to {args.output}")


if __name__ == "__main__":
    main()
