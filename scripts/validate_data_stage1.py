"""Validate the stage-1 Freesound manifest and downloaded previews."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("data/metadata/freesound_candidates.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/stage1_validation.json"))
    parser.add_argument("--target-per-category", type=int, default=10)
    args = parser.parse_args()

    with args.manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))

    category_counts = Counter(row["category"] for row in rows)
    license_counts = Counter(row["license_code"] for row in rows)
    preview_kind_counts = Counter(row["preview_kind"] for row in rows)
    sound_ids = [row["freesound_id"] for row in rows]
    missing_files: list[str] = []
    hash_mismatches: list[str] = []
    out_of_range: list[str] = []
    total_bytes = 0
    hashes: dict[str, list[str]] = defaultdict(list)

    for row in rows:
        path = Path(row["local_path"])
        if not path.exists():
            missing_files.append(row["freesound_id"])
            continue
        total_bytes += path.stat().st_size
        actual_hash = sha256_file(path)
        hashes[actual_hash].append(row["freesound_id"])
        if actual_hash.lower() != row["preview_sha256"].lower():
            hash_mismatches.append(row["freesound_id"])
        duration = float(row["duration_seconds"])
        if duration < 5 or duration > 120:
            out_of_range.append(row["freesound_id"])

    duplicate_sound_ids = sorted(sound_id for sound_id, count in Counter(sound_ids).items() if count > 1)
    duplicate_preview_hashes = {
        digest: ids for digest, ids in hashes.items() if len(ids) > 1
    }
    underfilled_categories = {
        category: count
        for category, count in category_counts.items()
        if count < args.target_per_category
    }
    critical_ok = not any(
        (missing_files, hash_mismatches, out_of_range, duplicate_sound_ids, duplicate_preview_hashes, underfilled_categories)
    )
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "critical_ok": critical_ok,
        "manifest_rows": len(rows),
        "unique_sound_ids": len(set(sound_ids)),
        "total_bytes": total_bytes,
        "category_counts": dict(sorted(category_counts.items())),
        "license_counts": dict(sorted(license_counts.items())),
        "preview_kind_counts": dict(sorted(preview_kind_counts.items())),
        "commercial_compatible": sum(row["commercial_compatible"].lower() == "true" for row in rows),
        "pending_review": sum(row["review_status"] == "pending" for row in rows),
        "missing_files": missing_files,
        "hash_mismatches": hash_mismatches,
        "out_of_duration_range": out_of_range,
        "duplicate_sound_ids": duplicate_sound_ids,
        "duplicate_preview_hashes": duplicate_preview_hashes,
        "underfilled_categories": underfilled_categories,
        "warnings": [
            "Public-web metadata must be rechecked before publication.",
            "Pending candidates are not approved training or test data.",
            "CC-BY-NC files must remain isolated from future commercial datasets.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if critical_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

