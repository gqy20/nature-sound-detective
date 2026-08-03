from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys


def run(command: list[str], *, allow_gate_failure: bool = False) -> int:
    print("+", " ".join(command), flush=True)
    completed = subprocess.run(command, check=False)
    if completed.returncode and not (allow_gate_failure and completed.returncode == 2):
        raise SystemExit(completed.returncode)
    return completed.returncode


def main() -> None:
    parser = argparse.ArgumentParser(description="运行可回归、可晋级的非鸟增量训练周期")
    parser.add_argument(
        "--feedback",
        type=Path,
        default=Path("data/metadata/nonbird_feedback_review_candidates.csv"),
    )
    parser.add_argument(
        "--base-manifest",
        type=Path,
        default=Path("data/metadata/nonbird_source_curated_prepared_manifest.csv"),
    )
    parser.add_argument(
        "--baseline-cache",
        type=Path,
        default=Path("artifacts/nonbird/source_curated_embeddings.npz"),
    )
    parser.add_argument(
        "--stress-cache",
        type=Path,
        default=Path("artifacts/nonbird/source_curated_stress_embeddings.npz"),
    )
    parser.add_argument(
        "--baseline-report",
        type=Path,
        default=Path("data/metadata/nonbird_source_curated_model_report.json"),
    )
    parser.add_argument("--run-id", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
    parser.add_argument("--version")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    root = Path("artifacts/nonbird/cycles") / args.run_id
    model_dir = root / "model"
    version = args.version or f"0.2.0+{args.run_id}"
    python = sys.executable
    combined = root / "training_manifest.csv"
    prepared = root / "prepared_manifest.csv"
    cache = root / "embeddings.npz"
    clean_report = root / "clean_report.json"
    stress_report = root / "stress_report.json"
    gate_report = root / "promotion_report.json"
    root.mkdir(parents=True, exist_ok=True)
    run(
        [
            python,
            "scripts/promote_reviewed_feedback.py",
            str(args.base_manifest),
            str(args.feedback),
            "--output",
            str(combined),
            "--require-new",
        ]
    )
    run(
        [
            python,
            "scripts/prepare_nonbird_training_audio.py",
            str(combined),
            "--output-manifest",
            str(prepared),
            "--audio-dir",
            str(root / "audio_48k"),
        ]
    )
    run([python, "scripts/extract_nonbird_embeddings.py", str(prepared), "--output", str(cache)])
    run([python, "scripts/train_nonbird_classifier.py", str(cache), "--output-dir", str(model_dir)])
    run(
        [
            python,
            "scripts/calibrate_nonbird_rejection.py",
            str(cache),
            str(model_dir),
            "--version",
            version,
        ]
    )
    run(
        [
            python,
            "scripts/evaluate_nonbird_classifier.py",
            str(args.baseline_cache),
            str(model_dir),
            "--output",
            str(clean_report),
        ]
    )
    run(
        [
            python,
            "scripts/evaluate_nonbird_robustness.py",
            str(args.stress_cache),
            str(model_dir),
            "--output",
            str(stress_report),
        ]
    )
    gate_code = run(
        [
            python,
            "scripts/compare_nonbird_models.py",
            str(args.baseline_report),
            str(clean_report),
            str(stress_report),
            "--output",
            str(gate_report),
        ],
        allow_gate_failure=True,
    )
    approved = gate_code == 0 and json.loads(gate_report.read_text(encoding="utf-8"))["approved"]
    if args.install and approved:
        run(
            [
                python,
                "scripts/export_nonbird_tflite.py",
                str(model_dir),
                "--output-dir",
                str(root / "export"),
                "--install-mobile",
                "--install-server",
            ]
        )
    elif args.install:
        print("candidate did not pass promotion gates; current model remains installed")
    print(f"cycle={root} approved={approved} installed={args.install and approved}")


if __name__ == "__main__":
    main()
