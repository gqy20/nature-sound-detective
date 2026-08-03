from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.build_nonbird_training_manifest import FIELDS, parse_intervals
from ml.nonbird.config import load_nonbird_config


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def promote(
    base_manifest: Path,
    feedback_candidates: Path,
    *,
    output: Path,
) -> tuple[list[dict[str, str]], int]:
    rows = read_rows(base_manifest)
    for row in rows:
        raw = Path(row.get("audio_path", ""))
        resolved = raw if raw.is_absolute() else (base_manifest.parent / raw).resolve()
        row["audio_path"] = os.path.relpath(resolved, output.parent.resolve())
    known_classes = set(load_nonbird_config().class_ids)
    known_recordings = {
        (row.get("source_dataset", ""), row.get("source_recording_id", ""))
        for row in rows
    }
    appended = 0
    for candidate in read_rows(feedback_candidates):
        if candidate.get("review_status") != "human_reviewed":
            continue
        taxon_id = candidate.get("taxon_id", "")
        if taxon_id not in known_classes:
            raise ValueError(f"未知反馈标签: {taxon_id}")
        identity = ("user_feedback", candidate.get("source_id", ""))
        if identity in known_recordings:
            continue
        local = Path(candidate.get("local_path", ""))
        local = local if local.is_absolute() else local.resolve()
        if not local.is_file():
            continue
        group = candidate.get("split_group", "")
        reviewer = candidate.get("reviewer", "").strip()
        if not group or not reviewer:
            raise ValueError("人工确认反馈必须包含 split_group 和 reviewer")
        for start, end in parse_intervals(candidate.get("valid_intervals", "")):
            rows.append(
                {
                    "audio_path": os.path.relpath(local, output.parent.resolve()),
                    "labels": taxon_id,
                    "split": "train",
                    "split_group": group,
                    "review_status": "human_reviewed",
                    "start_seconds": start,
                    "end_seconds": end,
                    "source_dataset": "user_feedback",
                    "source_recording_id": candidate.get("source_id", ""),
                    "source_url": "",
                    "license": "USER-CONSENT",
                    "commercial_compatible": "false",
                    "reviewer": reviewer,
                }
            )
        known_recordings.add(identity)
        appended += 1
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    return rows, appended


def main() -> None:
    parser = argparse.ArgumentParser(description="将人工确认的反馈追加到固定划分训练清单")
    parser.add_argument("base_manifest", type=Path)
    parser.add_argument("feedback_candidates", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-new", action="store_true")
    args = parser.parse_args()
    rows, appended = promote(
        args.base_manifest,
        args.feedback_candidates,
        output=args.output,
    )
    if args.require_new and not appended:
        raise SystemExit("没有新增 human_reviewed 反馈，取消训练周期")
    print(f"wrote {len(rows)} rows; appended {appended} reviewed feedback recordings")


if __name__ == "__main__":
    main()
