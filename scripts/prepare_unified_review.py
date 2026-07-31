"""Prepare existing recordings and a unified listening queue without moving originals."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
from collections import Counter
from pathlib import Path


CORE_SPECIES = {"鹊鸲", "白头鹎", "乌鸫", "珠颈斑鸠", "红嘴蓝鹊", "黑水鸡"}
HUMAN_FIELDS = (
    "human_final_class", "human_contains_speech", "human_contains_target_species",
    "human_valid_intervals", "human_reviewer", "human_reviewed_at", "human_review_notes",
)
MACHINE_PRESERVE_FIELDS = (
    "quality_flag", "rms_dbfs", "peak_dbfs", "silent_block_fraction",
    "clipping_sample_fraction", "quality_read_error",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    fields = sorted({key for row in rows for key in row})
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader(); writer.writerows(rows)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing-index", type=Path, default=Path("data/metadata/existing_recordings.csv"))
    parser.add_argument("--existing-queue", type=Path, default=Path("data/metadata/existing_review_queue.csv"))
    parser.add_argument("--freesound-order", type=Path, default=Path("data/metadata/freesound_manual_review_order.csv"))
    parser.add_argument("--unified-order", type=Path, default=Path("data/metadata/unified_review_order.csv"))
    parser.add_argument("--stage2-recordings", type=Path, default=Path("data/metadata/stage2_recording_baseline.csv"))
    parser.add_argument("--existing-decode-report", type=Path, default=Path("data/metadata/existing_decode_check.csv"))
    args = parser.parse_args()

    indexed = read_csv(args.existing_index)
    old = {row["item_id"]: row for row in read_csv(args.existing_queue)} if args.existing_queue.exists() else {}
    stage2 = {
        row["recording_id"]: row for row in read_csv(args.stage2_recordings)
    } if args.stage2_recordings.exists() else {}
    decode_report = {
        row["item_id"]: row for row in read_csv(args.existing_decode_report)
    } if args.existing_decode_report.exists() else {}
    hash_counts = Counter(row["sha256"] for row in indexed)
    existing_rows: list[dict[str, str]] = []
    for source in indexed:
        name_hash = hashlib.sha1(source["recording_id"].encode("utf-8")).hexdigest()[:8]
        item_id = f"existing_{source['sha256'][:12]}_{name_hash}"
        mixed = source.get("mixture_hint", "").lower() == "true"
        duplicate = hash_counts[source["sha256"]] > 1
        target = source["primary_label_weak"] in CORE_SPECIES
        reasons = []
        if mixed: reasons.append("filename_indicates_mixed_species")
        if duplicate: reasons.append("exact_duplicate_content")
        if source["source"] == "local_or_shared": reasons.append("license_and_origin_check")
        if target: reasons.append("core_species_positive_candidate")
        baseline = stage2.get(source["recording_id"], {})
        decode = decode_report.get(item_id, {})
        best_confidence = float(baseline.get("expected_best_confidence") or 0)
        if target and best_confidence < 0.25:
            reasons.append("birdnet_did_not_confirm_filename_label")
        if not reasons: reasons.append("species_label_confirmation")
        row = {
            **source,
            "dataset_key": "existing",
            "item_id": item_id,
            "name": source["filename"],
            "local_path": source["current_path"],
            "category": "existing_species_recording",
            "category_name_zh": "既有物种录音",
            "provisional_class": "mixed_species_review" if mixed else "positive_species_candidate",
            "contains_speech": "unchecked",
            "contains_target_species": (
                "birdnet_supports_filename_needs_listening" if target and best_confidence >= 0.25
                else "filename_positive_birdnet_not_confirmed" if target
                else "possible_core_species_needs_listening" if float(baseline.get("top_target_confidence") or 0) >= 0.25
                else "non_core_species_filename"
            ),
            "birdnet_max_confidence": baseline.get("expected_best_confidence", ""),
            "birdnet_top_species": baseline.get("top_target_species", ""),
            "privacy_risk": "unknown_needs_listening",
            "quality_flag": "unchecked",
            "decode_status": decode.get("decode_status") or ("indexed_readable" if not source.get("read_error") else "decode_failed"),
            "codec_stderr": decode.get("codec_stderr", ""),
            "license_code": source.get("license") or "UNKNOWN",
            "review_priority": "1" if mixed or duplicate or target or source.get("read_error") else "2",
            "review_reasons": "|".join(reasons),
            "review_recommendation": "listen_before_accept_or_reject",
            "review_status": "machine_labeled_needs_listening",
        }
        prior = old.get(item_id, {})
        for field in HUMAN_FIELDS + MACHINE_PRESERVE_FIELDS:
            row[field] = prior.get(field, "")
        if row["human_final_class"]:
            row["review_status"] = "human_reviewed"
        existing_rows.append(row)

    existing_rows.sort(key=lambda row: (int(row["review_priority"]), row["primary_label_weak"], row["filename"]))
    write_csv(args.existing_queue, existing_rows)

    freesound = read_csv(args.freesound_order)
    for row in freesound:
        row.setdefault("dataset_key", "freesound")
        row.setdefault("item_id", f"freesound_{row['freesound_id']}")
    unified = existing_rows + freesound
    unified.sort(key=lambda row: (int(row["review_priority"]), 0 if row["dataset_key"] == "existing" else 1, row["item_id"]))
    write_csv(args.unified_order, unified)
    print(f"existing_rows={len(existing_rows)}")
    print(f"unified_rows={len(unified)}")
    print(f"exact_duplicate_rows={sum(hash_counts[row['sha256']] > 1 for row in indexed)}")
    print(f"core_species_filename_candidates={sum(row['primary_label_weak'] in CORE_SPECIES for row in indexed)}")
    print(f"unified_order={args.unified_order.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
