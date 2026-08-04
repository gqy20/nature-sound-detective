from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import heapq
import json
from pathlib import Path
import sys
from typing import Any

import birdnet
import numpy as np


FIELDS = (
    "candidate_id",
    "source",
    "source_id",
    "taxon_id",
    "name_zh",
    "scientific_name",
    "category_id",
    "period",
    "captured_at",
    "local_path",
    "relative_path",
    "start_seconds",
    "end_seconds",
    "reference_similarity",
    "license_code",
    "attribution",
    "locality",
    "split_group",
    "valid_intervals",
    "review_status",
    "reviewer",
    "reviewed_label",
    "review_notes",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


def normalize(values: np.ndarray) -> np.ndarray:
    return values / np.maximum(np.linalg.norm(values, axis=1, keepdims=True), 1e-9)


def stratified(rows: list[dict[str, str]], maximum: int | None) -> list[dict[str, str]]:
    if maximum is None or len(rows) <= maximum:
        return rows
    ordered = sorted(rows, key=lambda row: (row["captured_at"], row["relative_path"]))
    indexes = np.linspace(0, len(ordered) - 1, maximum, dtype=int)
    return [ordered[int(index)] for index in indexes]


def main() -> None:
    parser = argparse.ArgumentParser(description="用官方虫蛙标准声嵌入检索野外候选")
    parser.add_argument("source_root", type=Path)
    parser.add_argument(
        "--index",
        type=Path,
        default=Path("data/metadata/challenge_2026_audio_index.csv"),
    )
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
        "--output",
        type=Path,
        default=Path("data/metadata/challenge_2026_nonbird_review_candidates.csv"),
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("data/metadata/challenge_2026_nonbird_retrieval_report.json"),
    )
    parser.add_argument("--max-files-per-period", type=int, default=96)
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--batch-files", type=int, default=16)
    parser.add_argument("--top-per-species-period", type=int, default=25)
    args = parser.parse_args()

    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))["classes"]
    targets = [row for row in catalog if row["category_id"] in {"insect", "frog"}]
    target_by_name = {str(row["name_zh"]): row for row in targets}
    references: dict[str, list[Path]] = {}
    for category_folder in ("虫", "蛙"):
        root = args.standard_root / category_folder
        for species_dir in sorted(path for path in root.iterdir() if path.is_dir()):
            canonical = next(
                (
                    row
                    for row in targets
                    if species_dir.name == row["name_zh"] or species_dir.name in row.get("aliases", [])
                ),
                None,
            )
            if canonical is None:
                continue
            references[str(canonical["taxon_id"])] = sorted(
                path
                for path in species_dir.iterdir()
                if path.suffix.lower() in {".wav", ".m4a", ".mp3"}
            )
    missing = sorted(str(row["name_zh"]) for row in targets if str(row["taxon_id"]) not in references)
    if missing:
        raise SystemExit(f"缺少官方标准声：{missing}")

    model = birdnet.load("acoustic", "2.4", "tf")
    reference_paths = [path for paths in references.values() for path in paths]
    reference_owner = {
        str(path.resolve()): taxon_id for taxon_id, paths in references.items() for path in paths
    }
    encoded_references = model.encode(
        [str(path.resolve()) for path in reference_paths],
        n_workers=1,
        batch_size=8,
        show_stats="minimal",
    ).to_dataframe().to_dict(orient="records")
    reference_features: dict[str, list[np.ndarray]] = {taxon_id: [] for taxon_id in references}
    for value in encoded_references:
        owner = reference_owner[str(Path(str(value["input"])).resolve())]
        reference_features[owner].append(np.asarray(value["embedding"], dtype=np.float32))
    reference_matrices = {
        taxon_id: normalize(np.stack(features)) for taxon_id, features in reference_features.items()
    }

    index_rows = [row for row in read_csv(args.index) if row["dataset_kind"] == "wild"]
    selected: list[dict[str, str]] = []
    periods = sorted({row["period"] for row in index_rows})
    for period in periods:
        period_rows = [row for row in index_rows if row["period"] == period]
        selected.extend(stratified(period_rows, None if args.full else args.max_files_per_period))
    row_by_path = {
        str((args.source_root / row["relative_path"]).resolve()): row for row in selected
    }
    heaps: dict[tuple[str, str], list[tuple[float, int, dict[str, Any]]]] = {
        (str(target["taxon_id"]), period): [] for target in targets for period in periods
    }
    sequence = 0
    for offset in range(0, len(selected), args.batch_files):
        batch = selected[offset : offset + args.batch_files]
        paths = [str((args.source_root / row["relative_path"]).resolve()) for row in batch]
        encoded = model.encode(
            paths,
            n_workers=1,
            batch_size=8,
            show_stats="minimal",
        ).to_dataframe().to_dict(orient="records")
        if not encoded:
            continue
        features = normalize(np.stack([np.asarray(value["embedding"], dtype=np.float32) for value in encoded]))
        for target in targets:
            taxon_id = str(target["taxon_id"])
            similarities = (features @ reference_matrices[taxon_id].T).max(axis=1)
            for value, similarity in zip(encoded, similarities, strict=True):
                path = str(Path(str(value["input"])).resolve())
                source = row_by_path[path]
                start = seconds(value["start_time"])
                end = seconds(value["end_time"])
                candidate = {
                    "candidate_id": f"{taxon_id}_{source['recording_id']}_{int(start * 1000):08d}",
                    "source": "shengshengbuxi_2026_wild",
                    "source_id": f"{taxon_id}_{source['recording_id']}_{int(start * 1000):08d}",
                    "taxon_id": taxon_id,
                    "name_zh": target["name_zh"],
                    "scientific_name": target["scientific_name"],
                    "category_id": target["category_id"],
                    "period": source["period"],
                    "captured_at": source["captured_at"],
                    "local_path": path,
                    "relative_path": source["relative_path"],
                    "start_seconds": round(start, 3),
                    "end_seconds": round(end, 3),
                    "reference_similarity": round(float(similarity), 6),
                    "license_code": "ORGANIZER_PROVIDED",
                    "attribution": "生声不息AI挑战赛项目组",
                    "locality": "杭州固定监测位点",
                    "split_group": source["recording_id"],
                    "valid_intervals": f"{start:.3f}-{end:.3f}",
                    "review_status": "pending",
                    "reviewer": "",
                    "reviewed_label": "",
                    "review_notes": "reference retrieval; not a species detection until reviewed",
                }
                key = (taxon_id, source["period"])
                item = (float(similarity), sequence, candidate)
                sequence += 1
                if len(heaps[key]) < args.top_per_species_period:
                    heapq.heappush(heaps[key], item)
                elif item[0] > heaps[key][0][0]:
                    heapq.heapreplace(heaps[key], item)
        print(f"encoded {min(offset + args.batch_files, len(selected))}/{len(selected)} files", flush=True)

    candidates = [item[2] for heap in heaps.values() for item in heap]
    candidates.sort(key=lambda row: (row["taxon_id"], row["period"], -float(row["reference_similarity"])))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(candidates)
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "method": "maximum cosine similarity to organizer-provided BirdNET reference embeddings",
        "warning": "候选只是检索排序，必须人工回听后才能作为训练标签或识别结果。",
        "full_scan": args.full,
        "indexed_wild_files": len(index_rows),
        "scanned_wild_files": len(selected),
        "scanned_duration_seconds": round(sum(float(row["duration_seconds"]) for row in selected), 3),
        "target_species": len(targets),
        "reference_files": len(reference_paths),
        "reference_windows": {key: len(value) for key, value in reference_features.items()},
        "candidate_rows": len(candidates),
        "top_per_species_period": args.top_per_species_period,
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
