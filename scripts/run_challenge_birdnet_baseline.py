from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time
from typing import Any

import birdnet


def load_catalog(path: Path) -> list[dict[str, Any]]:
    return list(json.loads(path.read_text(encoding="utf-8"))["classes"])


def load_birdnet_labels(path: Path) -> dict[str, str]:
    value = json.loads(path.read_text(encoding="utf-8"))
    labels: dict[str, str] = {}
    for row in value["species"]:
        scientific = str(row["scientific_name"])
        labels[scientific] = f"{scientific}_{row['name_en']}"
    return labels


def seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fields = sorted({key for row in rows for key in row}) if rows else ["empty"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="运行挑战赛12种鸟类官方标准声BirdNET基线")
    parser.add_argument(
        "--standard-root",
        type=Path,
        default=Path("data/interim/challenge_2026_standard_48k_v2"),
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path("ml/configs/challenge_2026_species.json"),
    )
    parser.add_argument(
        "--birdnet-labels",
        type=Path,
        default=Path("mobile/assets/labels/birdnet_hz.json"),
    )
    parser.add_argument(
        "--detections",
        type=Path,
        default=Path("data/metadata/challenge_2026_birdnet_standard_detections.csv"),
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("data/metadata/challenge_2026_birdnet_standard_report.json"),
    )
    args = parser.parse_args()

    standard_root = args.standard_root.resolve()
    catalog = load_catalog(args.catalog)
    birdnet_labels = load_birdnet_labels(args.birdnet_labels)
    species_by_name = {str(row["name_zh"]): row for row in catalog if row["category_id"] == "bird"}
    expected_labels: dict[str, str] = {}
    missing_labels: list[str] = []
    for name, row in species_by_name.items():
        scientific = row.get("birdnet_scientific_name")
        if scientific and scientific in birdnet_labels:
            expected_labels[name] = birdnet_labels[str(scientific)]
        else:
            missing_labels.append(name)

    bird_root = standard_root / "鸟"
    sources = sorted(path for path in bird_root.rglob("*") if path.suffix.lower() in {".wav", ".mp3", ".m4a"})
    if not sources:
        raise SystemExit(f"没有找到官方鸟类标准声：{bird_root}")
    resolved_sources = [path for path in sources if path.parent.name in expected_labels]
    started = time.perf_counter()
    model = birdnet.load("acoustic", "2.4", "tf")
    predictions = model.predict(
        [str(path.resolve()) for path in resolved_sources],
        custom_species_list=list(expected_labels.values()),
        top_k=6,
        default_confidence_threshold=0.01,
        n_producers=1,
        n_workers=1,
        batch_size=8,
        prefetch_ratio=1,
        show_stats="minimal",
    ).to_dataframe().to_dict(orient="records")
    elapsed = time.perf_counter() - started
    reverse = {label: name for name, label in expected_labels.items()}
    by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)
    rows: list[dict[str, Any]] = []
    for prediction in predictions:
        path = str(Path(str(prediction["input"])).resolve())
        source = Path(path)
        expected_name = source.parent.name
        label = str(prediction["species_name"])
        row = {
            "source_path": source.relative_to(standard_root).as_posix(),
            "expected_name_zh": expected_name,
            "expected_birdnet_label": expected_labels[expected_name],
            "candidate_name_zh": reverse.get(label, ""),
            "candidate_birdnet_label": label,
            "confidence": round(float(prediction["confidence"]), 6),
            "start_seconds": round(seconds(prediction["start_time"]), 3),
            "end_seconds": round(seconds(prediction["end_time"]), 3),
            "is_expected": label == expected_labels[expected_name],
        }
        rows.append(row)
        by_path[path].append(row)

    recordings: list[dict[str, Any]] = []
    for source in resolved_sources:
        path = str(source.resolve())
        expected = expected_labels[source.parent.name]
        matches = [row for row in by_path[path] if row["candidate_birdnet_label"] == expected]
        best = max((float(row["confidence"]) for row in matches), default=0.0)
        recordings.append(
            {
                "source_path": source.relative_to(standard_root).as_posix(),
                "species_name_zh": source.parent.name,
                "best_expected_confidence": round(best, 6),
                "hit_at_0_05": best >= 0.05,
                "hit_at_0_25": best >= 0.25,
                "hit_at_0_50": best >= 0.50,
            }
        )

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "baseline": "BirdNET acoustic 2.4 on organizer-provided standard sounds",
        "warning": "标准声仅用于覆盖检查和初始校准，不是独立野外测试集。",
        "runtime_seconds": round(elapsed, 3),
        "target_bird_species": len(species_by_name),
        "birdnet_mapped_species": len(expected_labels),
        "taxonomy_conflicts": missing_labels,
        "evaluated_recordings": len(recordings),
        "recall_at_0_05": round(sum(row["hit_at_0_05"] for row in recordings) / len(recordings), 4),
        "recall_at_0_25": round(sum(row["hit_at_0_25"] for row in recordings) / len(recordings), 4),
        "recall_at_0_50": round(sum(row["hit_at_0_50"] for row in recordings) / len(recordings), 4),
        "recordings_by_species": dict(Counter(row["species_name_zh"] for row in recordings)),
        "recordings": recordings,
        "detection_rows": len(rows),
    }
    write_csv(args.detections, rows)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
