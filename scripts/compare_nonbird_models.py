from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.training import write_json


SPECIFIC_CLASSES = ("cryptotympana_atrata", "polypedates_braueri")


def promotion_report(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    stress: dict[str, Any],
    *,
    minimum_specific_precision: float = 0.9,
    maximum_f1_drop: float = 0.08,
    maximum_background_false_positive_rate: float = 0.05,
) -> dict[str, Any]:
    reasons: list[str] = []
    baseline_metrics = baseline["test_metrics"] if "test_metrics" in baseline else baseline["metrics"]
    candidate_metrics = candidate["metrics"]
    comparisons: dict[str, dict[str, float]] = {}
    for class_id, baseline_metric in baseline_metrics.items():
        if class_id not in candidate_metrics:
            reasons.append(f"candidate missing class {class_id}")
            continue
        candidate_metric = candidate_metrics[class_id]
        drop = float(baseline_metric["f1"]) - float(candidate_metric["f1"])
        comparisons[class_id] = {
            "baseline_f1": float(baseline_metric["f1"]),
            "candidate_f1": float(candidate_metric["f1"]),
            "f1_drop": round(drop, 4),
        }
        if class_id != "background" and drop > maximum_f1_drop:
            reasons.append(f"{class_id} F1 drop {drop:.4f} exceeds {maximum_f1_drop:.4f}")
    for class_id in SPECIFIC_CLASSES:
        precision = float(candidate_metrics.get(class_id, {}).get("precision", 0))
        if precision < minimum_specific_precision:
            reasons.append(
                f"{class_id} precision {precision:.4f} below {minimum_specific_precision:.4f}"
            )
    background = stress.get("conditions", {}).get("background_clean", {})
    background_fpr = float(background.get("false_positive_rate", 1.0))
    if background_fpr > maximum_background_false_positive_rate:
        reasons.append(
            f"background false positive rate {background_fpr:.4f} exceeds "
            f"{maximum_background_false_positive_rate:.4f}"
        )
    return {
        "approved": not reasons,
        "reasons": reasons,
        "thresholds": {
            "minimum_specific_precision": minimum_specific_precision,
            "maximum_f1_drop": maximum_f1_drop,
            "maximum_background_false_positive_rate": maximum_background_false_positive_rate,
        },
        "background_false_positive_rate": background_fpr,
        "class_comparisons": comparisons,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="比较候选非鸟模型并决定是否允许安装")
    parser.add_argument("baseline_report", type=Path)
    parser.add_argument("candidate_report", type=Path)
    parser.add_argument("stress_report", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--minimum-specific-precision", type=float, default=0.9)
    parser.add_argument("--maximum-f1-drop", type=float, default=0.08)
    parser.add_argument("--maximum-background-fpr", type=float, default=0.05)
    args = parser.parse_args()
    reports = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in (args.baseline_report, args.candidate_report, args.stress_report)
    ]
    report = promotion_report(
        *reports,
        minimum_specific_precision=args.minimum_specific_precision,
        maximum_f1_drop=args.maximum_f1_drop,
        maximum_background_false_positive_rate=args.maximum_background_fpr,
    )
    write_json(args.output, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report["approved"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
