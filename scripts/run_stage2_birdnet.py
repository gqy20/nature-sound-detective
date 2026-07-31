"""Run the stage-2 BirdNET baseline on indexed recordings and build segment candidates."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import birdnet


TARGET_LABELS = {
    "鹊鸲": "Copsychus saularis_Oriental Magpie-Robin",
    "白头鹎": "Pycnonotus sinensis_Light-vented Bulbul",
    "乌鸫": "Turdus mandarinus_Chinese Blackbird",
    "珠颈斑鸠": "Streptopelia chinensis_Spotted Dove",
    "红嘴蓝鹊": "Urocissa erythroryncha_Red-billed Blue-Magpie",
    "黑水鸡": "Gallinula chloropus_Eurasian Moorhen",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({key for row in rows for key in row}) if rows else ["empty"]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader(); writer.writerows(rows)


def seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


def stable_split(group: str) -> str:
    bucket = int(hashlib.sha256(group.encode()).hexdigest()[:8], 16) % 100
    return "train" if bucket < 70 else "validation" if bucket < 85 else "test"


def assign_candidate_splits(segments: list[dict[str, Any]]) -> None:
    """Stratify source groups where possible; never split one source across sets."""
    positive: dict[str, set[str]] = defaultdict(set)
    negative: set[str] = set()
    for row in segments:
        if row["label"] == "background":
            negative.add(str(row["source_group"]))
        else:
            positive[str(row["label"])].add(str(row["source_group"]))

    assignments: dict[str, str] = {}
    for label, groups in sorted(positive.items()):
        ordered = sorted(groups)
        if len(ordered) >= 3:
            preferred = ["train", "validation", "test"]
        elif len(ordered) == 2:
            preferred = ["train", "validation"]
        else:
            preferred = ["train"]
        for index, group in enumerate(ordered):
            assignments[group] = preferred[index % len(preferred)]

    ordered_negative = sorted(negative)
    for index, group in enumerate(ordered_negative):
        fraction = index / max(len(ordered_negative), 1)
        assignments[group] = "train" if fraction < 0.70 else "validation" if fraction < 0.85 else "test"
    for row in segments:
        row["split"] = assignments[str(row["source_group"])]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--existing", type=Path, default=Path("data/metadata/existing_recordings.csv"))
    parser.add_argument("--background", type=Path, default=Path("data/metadata/freesound_shortlist_candidates.csv"))
    parser.add_argument("--detections", type=Path, default=Path("data/metadata/stage2_birdnet_detections.csv"))
    parser.add_argument("--recordings", type=Path, default=Path("data/metadata/stage2_recording_baseline.csv"))
    parser.add_argument("--segments", type=Path, default=Path("data/metadata/stage2_segment_candidates.csv"))
    parser.add_argument("--report", type=Path, default=Path("artifacts/baseline/stage2_birdnet_baseline.json"))
    parser.add_argument("--reuse-detections", action="store_true")
    args = parser.parse_args()

    existing = read_csv(args.existing)
    paths = [str(Path(row["current_path"]).resolve()) for row in existing]
    path_to_source = {str(Path(row["current_path"]).resolve()): row for row in existing}
    reverse = {label: zh for zh, label in TARGET_LABELS.items()}
    by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)
    detection_rows: list[dict[str, Any]] = []
    if args.reuse_detections and args.detections.exists():
        elapsed = 0.0
        detection_rows = read_csv(args.detections)
        for row in detection_rows:
            by_path[str(Path(row["local_path"]).resolve())].append(row)
    else:
        started = time.perf_counter()
        model = birdnet.load("acoustic", "2.4", "tf")
        predictions = model.predict(
            paths,
            custom_species_list=list(TARGET_LABELS.values()),
            top_k=6,
            default_confidence_threshold=0.05,
            n_producers=2,
            n_workers=1,
            batch_size=8,
            prefetch_ratio=2,
            show_stats="minimal",
        ).to_dataframe().to_dict(orient="records")
        elapsed = time.perf_counter() - started
        for prediction in predictions:
            path = str(Path(str(prediction["input"])).resolve())
            source = path_to_source[path]
            label = str(prediction["species_name"])
            row = {
                "recording_id": source["recording_id"], "sha256": source["sha256"],
                "local_path": path, "primary_label_weak": source["primary_label_weak"],
                "species_name_zh": reverse.get(label, ""), "species_label": label,
                "confidence": round(float(prediction["confidence"]), 6),
                "start_seconds": round(seconds(prediction["start_time"]), 3),
                "end_seconds": round(seconds(prediction["end_time"]), 3),
            }
            detection_rows.append(row); by_path[path].append(row)

    recording_rows: list[dict[str, Any]] = []
    evaluation_rows: list[dict[str, Any]] = []
    segments: list[dict[str, Any]] = []
    seen_positive_segments: set[tuple[str, float, str]] = set()
    for source in existing:
        path = str(Path(source["current_path"]).resolve())
        detections = sorted(by_path.get(path, []), key=lambda row: float(row["confidence"]), reverse=True)
        expected = TARGET_LABELS.get(source["primary_label_weak"], "")
        expected_detections = [row for row in detections if row["species_label"] == expected]
        best = max((float(row["confidence"]) for row in expected_detections), default=0.0)
        eligible = bool(expected and source["source"] == "xeno_canto" and source["mixture_hint"].lower() != "true")
        result = {
            **source,
            "expected_species_label": expected,
            "expected_best_confidence": round(best, 6),
            "detected_at_0_25": best >= 0.25,
            "detected_at_0_50": best >= 0.50,
            "top_target_species": detections[0]["species_name_zh"] if detections else "",
            "top_target_confidence": detections[0]["confidence"] if detections else 0.0,
            "evaluation_eligible": eligible,
        }
        recording_rows.append(result)
        if eligible: evaluation_rows.append(result)
        if eligible:
            for detection in expected_detections:
                if float(detection["confidence"]) < 0.25: continue
                key = (source["sha256"], float(detection["start_seconds"]), expected)
                if key in seen_positive_segments: continue
                seen_positive_segments.add(key)
                segments.append({
                    "segment_id": f"pos_{source['sha256'][:12]}_{int(float(detection['start_seconds'])*1000):08d}",
                    "source_group": source["sha256"], "split": stable_split(source["sha256"]),
                    "local_path": source["current_path"], "start_seconds": detection["start_seconds"],
                    "end_seconds": detection["end_seconds"], "label": source["primary_label_weak"],
                    "label_type": "birdnet_candidate_needs_listening", "confidence": detection["confidence"],
                })

    for background in read_csv(args.background):
        group = background["preview_sha256"]
        duration = min(3.0, float(background["duration_seconds"]))
        segments.append({
            "segment_id": f"neg_{group[:12]}_00000000", "source_group": group,
            "split": stable_split(group), "local_path": background["local_path"],
            "start_seconds": 0.0, "end_seconds": round(duration, 3), "label": "background",
            "label_type": "background_candidate_needs_listening", "confidence": "",
        })

    assign_candidate_splits(segments)
    write_csv(args.detections, detection_rows)
    write_csv(args.recordings, recording_rows)
    write_csv(args.segments, segments)
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "report_type": "stage2_recording_level_weak_label_baseline",
        "warning": "Filename labels and BirdNET segment proposals require human listening confirmation.",
        "runtime_seconds": round(elapsed, 3),
        "recordings_scanned": len(existing),
        "evaluation_recordings": len(evaluation_rows),
        "evaluation_unique_audio": len({row["sha256"] for row in evaluation_rows}),
        "recall_at_0_25": round(sum(row["detected_at_0_25"] for row in evaluation_rows) / len(evaluation_rows), 4) if evaluation_rows else None,
        "recall_at_0_50": round(sum(row["detected_at_0_50"] for row in evaluation_rows) / len(evaluation_rows), 4) if evaluation_rows else None,
        "evaluation_by_species": dict(Counter(row["primary_label_weak"] for row in evaluation_rows)),
        "detection_rows": len(detection_rows),
        "segment_candidates": len(segments),
        "segment_label_counts": dict(Counter(row["label"] for row in segments)),
        "segment_split_counts": dict(Counter(row["split"] for row in segments)),
        "segment_source_group_split_counts": dict(
            Counter({row["source_group"]: row["split"] for row in segments}.values())
        ),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"segments={args.segments.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
