"""Validate unified review data and stage-2 segment candidates."""

from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


def read(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> int:
    existing = read(Path("data/metadata/existing_review_queue.csv"))
    unified = read(Path("data/metadata/unified_review_order.csv"))
    segments = read(Path("data/metadata/stage2_segment_candidates.csv"))
    split_by_group: dict[str, set[str]] = defaultdict(set)
    for row in segments:
        split_by_group[row["source_group"]].add(row["split"])
    missing = [row["local_path"] for row in unified if not Path(row["local_path"]).exists()]
    duplicate_item_ids = [key for key, count in Counter(row["item_id"] for row in unified).items() if count > 1]
    leaking_groups = [group for group, splits in split_by_group.items() if len(splits) > 1]
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "critical_ok": not missing and not duplicate_item_ids and not leaking_groups,
        "existing_review_rows": len(existing),
        "unified_review_rows": len(unified),
        "unified_dataset_counts": dict(Counter(row["dataset_key"] for row in unified)),
        "missing_audio": missing,
        "duplicate_item_ids": duplicate_item_ids,
        "stage2_segments": len(segments),
        "segment_label_counts": dict(Counter(row["label"] for row in segments)),
        "segment_split_counts": dict(Counter(row["split"] for row in segments)),
        "source_groups": len(split_by_group),
        "leaking_source_groups": leaking_groups,
        "warning": "Segment labels remain machine-assisted candidates until human listening review.",
    }
    output = Path("data/metadata/stage2_validation.json")
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["critical_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
