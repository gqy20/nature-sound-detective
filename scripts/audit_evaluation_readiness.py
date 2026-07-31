"""Report which Hangzhou MVP classes still lack verified evaluation samples."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.evaluation_readiness import load_species_targets, readiness_report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("data/metadata/mvp_evaluation_manifest.csv"))
    parser.add_argument("--species-config", type=Path, default=Path("ml/configs/hangzhou_mvp_species.json"))
    parser.add_argument("--sound-minimum", type=int, default=5)
    parser.add_argument("--species-minimum", type=int, default=10)
    parser.add_argument("--output", type=Path, default=Path("artifacts/evaluation/readiness.json"))
    args = parser.parse_args()

    with args.manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    report = readiness_report(
        rows, load_species_targets(args.species_config), args.sound_minimum, args.species_minimum
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"output={args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
