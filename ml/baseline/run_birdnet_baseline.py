"""Run a small, reproducible BirdNET baseline on labelled workspace audio.

This script intentionally treats filenames as weak labels. Its report is a pipeline
baseline, not a publishable model evaluation. Formal evaluation requires manually
reviewed clips and recording-level train/test separation.
"""

from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import birdnet


@dataclass(frozen=True)
class Sample:
    path: Path
    expected_zh: str
    expected_scientific: str


DEFAULT_PATTERNS = {
    "乌鸫": ("Turdus mandarinus", "*乌鸫*"),
    "白头鹎": ("Pycnonotus sinensis", "*白头鹎*"),
    "珠颈斑鸠": ("Streptopelia chinensis", "*珠颈斑鸠*"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/baseline/birdnet_baseline.json"))
    parser.add_argument("--model-version", default="2.4")
    parser.add_argument("--backend", default="tf")
    parser.add_argument("--max-per-class", type=int, default=2)
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--species", choices=sorted(DEFAULT_PATTERNS), help="Run only one weak-label class")
    return parser.parse_args()


def select_samples(data_dir: Path, max_per_class: int, selected_species: str | None = None) -> list[Sample]:
    samples: list[Sample] = []
    for name_zh, (scientific_name, pattern) in DEFAULT_PATTERNS.items():
        if selected_species and name_zh != selected_species:
            continue
        candidates = [
            p for p in data_dir.glob(pattern) if p.is_file() and p.suffix.lower() in {".wav", ".mp3", ".flac", ".ogg"}
        ]
        candidates.sort(
            key=lambda path: (
                scientific_name.lower() not in path.name.lower(),
                not path.name.upper().startswith("XC"),
                path.name,
            )
        )
        for path in candidates[:max_per_class]:
            samples.append(Sample(path.resolve(), name_zh, scientific_name))
    return samples


def normalize_rows(predictions: Any) -> list[dict[str, Any]]:
    if hasattr(predictions, "to_dataframe"):
        predictions = predictions.to_dataframe()
    if hasattr(predictions, "to_dict"):
        return predictions.to_dict(orient="records")
    if isinstance(predictions, list):
        return [dict(row) if not isinstance(row, dict) else row for row in predictions]
    raise TypeError(f"Unsupported prediction result: {type(predictions)!r}")


def confidence(row: dict[str, Any]) -> float:
    return float(row.get("confidence", row.get("score", 0.0)))


def species_name(row: dict[str, Any]) -> str:
    return str(row.get("species_name", row.get("label", "")))


def main() -> int:
    args = parse_args()
    samples = select_samples(args.data_dir, args.max_per_class, args.species)
    if not samples:
        raise SystemExit(f"No labelled samples found in {args.data_dir}")

    started = time.perf_counter()
    model = birdnet.load("acoustic", args.model_version, args.backend)
    load_seconds = time.perf_counter() - started

    results: list[dict[str, Any]] = []
    for sample in samples:
        inference_started = time.perf_counter()
        predictions = model.predict(str(sample.path))
        inference_seconds = time.perf_counter() - inference_started
        rows = normalize_rows(predictions)
        ranked = sorted(rows, key=confidence, reverse=True)

        expected_rows = [
            row for row in ranked if sample.expected_scientific.lower() in species_name(row).lower()
        ]
        best_expected = expected_rows[0] if expected_rows else None
        expected_rank = (
            next(
                (index for index, row in enumerate(ranked, start=1) if sample.expected_scientific.lower() in species_name(row).lower()),
                None,
            )
        )

        results.append(
            {
                "sample": asdict(sample) | {"path": str(sample.path)},
                "inference_seconds": round(inference_seconds, 4),
                "prediction_rows": len(rows),
                "expected_rank": expected_rank,
                "expected_best_confidence": round(confidence(best_expected), 6) if best_expected else None,
                "top_predictions": [
                    {
                        "species_name": species_name(row),
                        "confidence": round(confidence(row), 6),
                        "start_time": str(row.get("start_time", "")),
                        "end_time": str(row.get("end_time", "")),
                    }
                    for row in ranked[: args.top_k]
                ],
            }
        )

    ranks = [item["expected_rank"] for item in results]
    summary = {
        "sample_count": len(results),
        "top_1_hits": sum(rank == 1 for rank in ranks),
        "top_3_hits": sum(rank is not None and rank <= 3 for rank in ranks),
        "target_detected": sum(rank is not None for rank in ranks),
        "mean_inference_seconds": round(
            sum(item["inference_seconds"] for item in results) / len(results), 4
        ),
    }
    report = {
        "report_type": "weak_filename_label_pipeline_baseline",
        "warning": "Not a formal accuracy evaluation; filenames may describe mixed or partial recordings.",
        "runtime": {
            "python": sys.version,
            "platform": platform.platform(),
            "birdnet": getattr(birdnet, "__version__", "unknown"),
            "model_version": args.model_version,
            "backend": args.backend,
            "model_load_seconds": round(load_seconds, 4),
        },
        "summary": summary,
        "results": results,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"Report: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
