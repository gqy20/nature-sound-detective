from __future__ import annotations

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from typing import Any

import birdnet
import numpy as np

from run_challenge_birdnet_baseline import load_birdnet_labels, load_catalog, seconds


FIELDS = (
    "detection_id",
    "recording_id",
    "period",
    "captured_at",
    "local_path",
    "relative_path",
    "start_seconds",
    "end_seconds",
    "taxon_id",
    "name_zh",
    "scientific_name",
    "birdnet_label",
    "confidence",
    "review_status",
    "reviewer",
    "review_notes",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def stratified(rows: list[dict[str, str]], maximum: int | None) -> list[dict[str, str]]:
    ordered = sorted(rows, key=lambda row: (row["captured_at"], row["relative_path"]))
    if maximum is None or len(ordered) <= maximum:
        return ordered
    return [ordered[int(index)] for index in np.linspace(0, len(ordered) - 1, maximum, dtype=int)]


def main() -> None:
    parser = argparse.ArgumentParser(description="运行挑战赛野外录音BirdNET候选基线")
    parser.add_argument("source_root", type=Path)
    parser.add_argument("--index", type=Path, default=Path("data/metadata/challenge_2026_audio_index.csv"))
    parser.add_argument("--catalog", type=Path, default=Path("ml/configs/challenge_2026_species.json"))
    parser.add_argument("--birdnet-labels", type=Path, default=Path("mobile/assets/labels/birdnet_hz.json"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/challenge_2026_wild_birdnet_candidates.csv"))
    parser.add_argument("--report", type=Path, default=Path("data/metadata/challenge_2026_wild_birdnet_report.json"))
    parser.add_argument("--max-files-per-period", type=int, default=24)
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args()

    catalog = [row for row in load_catalog(args.catalog) if row["category_id"] == "bird"]
    available = load_birdnet_labels(args.birdnet_labels)
    targets = [
        row
        for row in catalog
        if row.get("birdnet_scientific_name") in available
    ]
    label_by_taxon = {
        str(row["taxon_id"]): available[str(row["birdnet_scientific_name"])] for row in targets
    }
    target_by_label = {label_by_taxon[str(row["taxon_id"])]: row for row in targets}
    indexed = [row for row in read_csv(args.index) if row["dataset_kind"] == "wild"]
    selected: list[dict[str, str]] = []
    for period in sorted({row["period"] for row in indexed}):
        selected.extend(
            stratified(
                [row for row in indexed if row["period"] == period],
                None if args.full else args.max_files_per_period,
            )
        )
    paths = [str((args.source_root / row["relative_path"]).resolve()) for row in selected]
    source_by_path = {
        str((args.source_root / row["relative_path"]).resolve()): row for row in selected
    }
    model = birdnet.load("acoustic", "2.4", "tf")
    started = time.perf_counter()
    predictions = model.predict(
        paths,
        custom_species_list=list(target_by_label),
        top_k=6,
        default_confidence_threshold=0.05,
        n_producers=2,
        n_workers=1,
        batch_size=8,
        prefetch_ratio=2,
        show_stats="minimal",
    ).to_dataframe().to_dict(orient="records")
    runtime = time.perf_counter() - started
    rows: list[dict[str, Any]] = []
    for prediction in predictions:
        path = str(Path(str(prediction["input"])).resolve())
        source = source_by_path[path]
        label = str(prediction["species_name"])
        target = target_by_label[label]
        start = seconds(prediction["start_time"])
        confidence = float(prediction["confidence"])
        rows.append(
            {
                "detection_id": f"{source['recording_id']}_{target['taxon_id']}_{int(start * 1000):08d}",
                "recording_id": source["recording_id"],
                "period": source["period"],
                "captured_at": source["captured_at"],
                "local_path": path,
                "relative_path": source["relative_path"],
                "start_seconds": round(start, 3),
                "end_seconds": round(seconds(prediction["end_time"]), 3),
                "taxon_id": target["taxon_id"],
                "name_zh": target["name_zh"],
                "scientific_name": target["scientific_name"],
                "birdnet_label": label,
                "confidence": round(confidence, 6),
                "review_status": "pending",
                "reviewer": "",
                "review_notes": "BirdNET候选；人工回听前不作为物种事实。",
            }
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "method": "BirdNET acoustic 2.4, eleven organizer target birds",
        "warning": "野外数据没有逐段真值；本报告是候选分布，不是准确率。",
        "full_scan": args.full,
        "indexed_files": len(indexed),
        "scanned_files": len(selected),
        "scanned_duration_seconds": round(sum(float(row["duration_seconds"]) for row in selected), 3),
        "runtime_seconds": round(runtime, 3),
        "candidate_rows": len(rows),
        "candidate_counts": dict(Counter(row["name_zh"] for row in rows)),
        "high_confidence_counts": dict(Counter(row["name_zh"] for row in rows if row["confidence"] >= 0.25)),
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
