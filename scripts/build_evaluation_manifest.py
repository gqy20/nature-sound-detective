"""Build a reviewable MVP evaluation manifest from the current local datasets."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.birdnet_service import SPECIES
from app.evaluation import FREESOUND_SOUND_TYPES


FIELDS = [
    "case_id", "local_path", "source", "expected_sound_types", "expected_species",
    "label_status", "label_source", "location", "include", "reviewer", "review_notes",
]
CORE_SPECIES = set(SPECIES.values())


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def existing_cases(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in read_csv(path):
        species = item.get("reviewed_primary_label") or item.get("primary_label_weak", "")
        reviewed = bool(item.get("reviewed_primary_label"))
        local_path = item.get("current_path") or item.get("local_path", "")
        rows.append({
            "case_id": f"existing_{item['recording_id']}",
            "local_path": local_path,
            "source": item.get("source", "existing"),
            "expected_sound_types": "鸟类鸣叫",
            "expected_species": species,
            "label_status": "verified" if reviewed else "weak",
            "label_source": "human_review" if reviewed else item.get("label_basis", "filename"),
            "location": "杭州",
            "include": "yes" if species in CORE_SPECIES else "no",
            "reviewer": "",
            "review_notes": "核心六种候选" if species in CORE_SPECIES else "超出当前 BirdNET 六种范围",
        })
    return rows


def freesound_cases(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for item in read_csv(path):
        category = item.get("category", "")
        expected = FREESOUND_SOUND_TYPES.get(category)
        if not expected or not item.get("local_path"):
            continue
        human_class = item.get("reviewed_class", "").strip()
        rows.append({
            "case_id": f"freesound_{item['freesound_id']}",
            "local_path": item["local_path"],
            "source": "freesound_preview",
            "expected_sound_types": "|".join(expected),
            "expected_species": "",
            "label_status": "verified" if human_class else "weak",
            "label_source": "human_review" if human_class else "freesound_category",
            "location": "杭州",
            "include": "yes",
            "reviewer": "",
            "review_notes": item.get("review_notes", ""),
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", type=Path, default=Path("data/metadata/existing_recordings.csv"))
    parser.add_argument("--freesound", type=Path, default=Path("data/metadata/freesound_candidates.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/mvp_evaluation_manifest.csv"))
    args = parser.parse_args()

    old: dict[str, dict[str, str]] = {}
    if args.output.exists():
        old = {row["case_id"]: row for row in read_csv(args.output)}
    rows = existing_cases(args.existing) + freesound_cases(args.freesound)
    for row in rows:
        previous = old.get(str(row["case_id"]), {})
        for field in ("label_status", "expected_sound_types", "expected_species", "include", "reviewer", "review_notes"):
            if previous.get(field):
                row[field] = previous[field]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"manifest={args.output.resolve()}")
    print(f"cases={len(rows)} included={sum(row['include'] == 'yes' for row in rows)} verified={sum(row['label_status'] == 'verified' for row in rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
