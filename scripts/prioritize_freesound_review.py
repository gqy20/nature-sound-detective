"""Build a conservative, ordered human-listening queue for Freesound previews.

This script never converts machine hints into final labels.  It only assigns
review priority and a shortlist recommendation so a human can listen to the
most risky or informative clips first.
"""

from __future__ import annotations

import argparse
import csv
import os
from collections import Counter
from pathlib import Path


def as_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def classify(row: dict[str, str]) -> tuple[int, list[str], str]:
    reasons: list[str] = []
    confidence = as_float(row.get("birdnet_max_confidence", ""))

    if row.get("privacy_risk") in {"high", "medium"} or row.get("contains_speech") == "possible":
        reasons.append("privacy_and_speech_check")
    if row.get("quality_flag") != "usable_level_candidate":
        reasons.append("audio_quality_check")
    if row.get("decode_status") not in {"", "ok"}:
        reasons.append("codec_integrity_check")
    if confidence >= 0.05:
        reasons.append("very_low_confidence_target_species_check")
    if row.get("provisional_class") == "mixed_or_unknown_candidate":
        reasons.append("mixed_soundscape_check")
    if row.get("metadata_bird_terms"):
        reasons.append("metadata_mentions_birds")
    if row.get("commercial_compatible", "").lower() != "true":
        reasons.append("noncommercial_license_check")

    if any(
        reason in reasons
        for reason in ("privacy_and_speech_check", "audio_quality_check", "codec_integrity_check")
    ):
        priority = 1
    elif any(
        reason in reasons
        for reason in (
            "very_low_confidence_target_species_check",
            "mixed_soundscape_check",
            "metadata_mentions_birds",
            "noncommercial_license_check",
        )
    ):
        priority = 2
    else:
        priority = 3

    conservative_shortlist = (
        row.get("provisional_class") == "background_candidate"
        and row.get("contains_speech") == "unlikely"
        and row.get("privacy_risk") == "low"
        and row.get("quality_flag") == "usable_level_candidate"
        and confidence < 0.05
        and row.get("commercial_compatible", "").lower() == "true"
    )
    recommendation = (
        "shortlist_after_human_spot_check"
        if conservative_shortlist
        else "listen_before_accept_or_reject"
    )
    return priority, reasons, recommendation


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--queue", type=Path, default=Path("data/metadata/freesound_review_queue.csv"))
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/metadata/freesound_manual_review_order.csv"),
    )
    parser.add_argument(
        "--shortlist",
        type=Path,
        default=Path("data/metadata/freesound_shortlist_candidates.csv"),
    )
    parser.add_argument(
        "--decode-report",
        type=Path,
        default=Path("data/metadata/freesound_decode_check.csv"),
    )
    args = parser.parse_args()

    with args.queue.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))

    if args.decode_report.exists():
        with args.decode_report.open("r", encoding="utf-8-sig", newline="") as handle:
            decode_by_id = {row["freesound_id"]: row for row in csv.DictReader(handle)}
        for row in rows:
            decode = decode_by_id.get(row["freesound_id"], {})
            row["decode_status"] = decode.get("decode_status", "")
            row["codec_stderr"] = decode.get("codec_stderr", "")

    for row in rows:
        row["dataset_key"] = "freesound"
        row["item_id"] = f"freesound_{row['freesound_id']}"
        priority, reasons, recommendation = classify(row)
        row["review_priority"] = str(priority)
        row["review_reasons"] = "|".join(reasons) if reasons else "routine_spot_check"
        row["review_recommendation"] = recommendation

    rows.sort(
        key=lambda row: (
            int(row["review_priority"]),
            row["category"],
            -as_float(row.get("birdnet_max_confidence", "")),
            int(row["freesound_id"]),
        )
    )
    shortlist = [
        row for row in rows if row["review_recommendation"] == "shortlist_after_human_spot_check"
    ]

    fields = sorted({key for row in rows for key in row})
    for path, output_rows in ((args.output, rows), (args.shortlist, shortlist)):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        with temporary.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(output_rows)
        os.replace(temporary, path)

    print(f"review_rows={len(rows)}")
    print(f"priority_counts={dict(sorted(Counter(row['review_priority'] for row in rows).items()))}")
    print(f"shortlist_candidates={len(shortlist)}")
    print(f"review_order={args.output.resolve()}")
    print(f"shortlist={args.shortlist.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
