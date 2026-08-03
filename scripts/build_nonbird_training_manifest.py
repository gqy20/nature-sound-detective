from __future__ import annotations

import argparse
import csv
import hashlib
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config


APPROVED = {"human_reviewed", "expert_confirmed", "approved", "source_curated"}
VALID_SPLITS = {"train", "validation", "test"}
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


def deterministic_split(group: str) -> str:
    bucket = int(hashlib.sha256(group.encode("utf-8")).hexdigest()[:8], 16) % 100
    if bucket < 70:
        return "train"
    if bucket < 85:
        return "validation"
    return "test"


def parse_intervals(value: str) -> list[tuple[str, str]]:
    if not value.strip():
        return [("", "")]
    intervals: list[tuple[str, str]] = []
    for part in value.split(";"):
        start, separator, end = part.partition("-")
        if not separator or float(start) < 0 or float(end) <= float(start):
            raise ValueError(f"无效有效区间: {value}")
        intervals.append((str(float(start)), str(float(end))))
    return intervals


def build_rows(paths: list[Path], *, output: Path, commercial_only: bool) -> list[dict[str, str]]:
    config = load_nonbird_config()
    valid_labels = set(config.class_ids)
    seen: set[str] = set()
    rows: list[dict[str, str]] = []
    for path in paths:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            for line_number, candidate in enumerate(csv.DictReader(handle), start=2):
                if candidate.get("review_status", "").strip() not in APPROVED:
                    continue
                label = candidate.get("taxon_id", "").strip()
                if label not in valid_labels:
                    raise ValueError(f"{path}:{line_number} 未知标签 {label}")
                commercial = candidate.get("commercial_compatible", "").strip().lower() == "true"
                if commercial_only and not commercial:
                    continue
                raw_audio = Path(candidate.get("local_path", "").strip())
                audio_path = raw_audio if raw_audio.is_absolute() else raw_audio.resolve()
                if not raw_audio.name or not audio_path.is_file():
                    continue
                group = candidate.get("split_group", "").strip()
                if not group:
                    raise ValueError(f"{path}:{line_number} 缺少 split_group")
                identity = candidate.get("sha256", "").strip() or f"{candidate.get('source')}:{candidate.get('source_id')}"
                if identity in seen:
                    continue
                seen.add(identity)
                split_hint = candidate.get("split_hint", "").strip().lower()
                split = split_hint if split_hint in VALID_SPLITS else deterministic_split(group)
                relative_audio = os.path.relpath(audio_path, output.parent.resolve())
                interval_text = candidate.get("valid_intervals", "") or candidate.get("reviewed_intervals", "")
                for start, end in parse_intervals(interval_text):
                    rows.append(
                        {
                            "audio_path": relative_audio,
                            "labels": label,
                            "split": split,
                            "split_group": group,
                            "review_status": candidate["review_status"],
                            "start_seconds": start,
                            "end_seconds": end,
                            "source_dataset": candidate.get("source", ""),
                            "source_recording_id": candidate.get("source_id", ""),
                            "source_url": candidate.get("source_url", ""),
                            "license": candidate.get("license_code", ""),
                            "commercial_compatible": str(commercial).lower(),
                            "reviewer": candidate.get("reviewer", ""),
                        }
                    )
    return rows


def write_manifest(rows: list[dict[str, str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="将已审核候选构建为非鸟分类头训练清单")
    parser.add_argument("candidates", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, default=Path("data/metadata/nonbird_training_manifest.csv"))
    parser.add_argument("--commercial-only", action="store_true")
    args = parser.parse_args()
    rows = build_rows(args.candidates, output=args.output, commercial_only=args.commercial_only)
    if not rows:
        raise SystemExit("没有可训练样本：请先下载音频并完成人工审核")
    write_manifest(rows, args.output)
    counts = {split: sum(row["split"] == split for row in rows) for split in sorted(VALID_SPLITS)}
    print(f"wrote {len(rows)} reviewed training rows to {args.output}: {counts}")


if __name__ == "__main__":
    main()
