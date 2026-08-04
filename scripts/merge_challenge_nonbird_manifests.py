from __future__ import annotations

import argparse
from collections import Counter
import csv
from pathlib import Path


FROG_TO_OTHER = {"hyla_chinensis", "kaloula_borealis", "polypedates_braueri"}
INSECT_TO_OTHER = {"planopleura_kaempferi"}
FIELDS = (
    "audio_path",
    "labels",
    "split",
    "split_group",
    "review_status",
    "start_seconds",
    "end_seconds",
    "source_dataset",
    "source_recording_id",
    "source_url",
    "license",
    "commercial_compatible",
    "reviewer",
)


def read(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def map_legacy_label(label: str) -> str:
    if label in FROG_TO_OTHER:
        return "other_frog"
    if label in INSECT_TO_OTHER:
        return "other_insect"
    return label


def main() -> None:
    parser = argparse.ArgumentParser(description="合并现有困难负样本与挑战赛新增虫蛙训练清单")
    parser.add_argument("legacy", type=Path)
    parser.add_argument("challenge", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    merged: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    # Prefer challenge-specific labels when a source also existed as a broad
    # "other frog/insect" example in the legacy manifest.
    for source_path, is_legacy in ((args.challenge, False), (args.legacy, True)):
        for row in read(source_path):
            key = (row.get("source_dataset", ""), row.get("source_recording_id", ""))
            if key in seen:
                continue
            seen.add(key)
            updated = {field: row.get(field, "") for field in FIELDS}
            if is_legacy:
                updated["labels"] = map_legacy_label(updated["labels"])
                raw = Path(updated["audio_path"])
                absolute = raw if raw.is_absolute() else (source_path.parent / raw).resolve()
                updated["audio_path"] = str(absolute)
            merged.append(updated)
    group_splits: dict[str, set[str]] = {}
    for row in merged:
        group_splits.setdefault(row["split_group"], set()).add(row["split"])
    leaking = [group for group, splits in group_splits.items() if len(splits) > 1]
    if leaking:
        raise ValueError(f"split_group跨集合泄漏：{leaking[:5]}")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(merged)
    counts = Counter((row["labels"], row["split"]) for row in merged)
    print(f"wrote {len(merged)} rows to {args.output}")
    print(dict(sorted(counts.items())))


if __name__ == "__main__":
    main()
