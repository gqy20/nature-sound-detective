from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.training import load_embedding_cache, metrics_at_thresholds, sigmoid, write_json


def robustness_report(
    cache: dict[str, np.ndarray],
    probabilities: np.ndarray,
    thresholds: np.ndarray,
) -> dict:
    class_ids = tuple(str(item) for item in cache["class_ids"])
    conditions = cache.get("conditions")
    if conditions is None or len(conditions) != len(cache["features"]):
        raise ValueError("压力测试缓存缺少 conditions")
    predicted = probabilities >= thresholds
    nonbackground = np.asarray([item != "background" for item in class_ids])
    result: dict[str, dict] = {}
    for condition in sorted({str(item) for item in conditions}):
        mask = conditions == condition
        truth = cache["targets"][mask]
        condition_predicted = predicted[mask]
        false_positive = np.logical_and(
            ~truth[:, nonbackground].any(axis=1),
            condition_predicted[:, nonbackground].any(axis=1),
        )
        windows = int(mask.sum())
        duration_minutes = windows * 3.0 / 60.0
        metrics = metrics_at_thresholds(truth, probabilities[mask], thresholds)
        result[condition] = {
            "windows": windows,
            "false_positive_windows": int(false_positive.sum()),
            "false_positive_rate": round(float(false_positive.mean()), 4) if windows else 0.0,
            "false_positive_windows_per_minute": round(
                float(false_positive.sum()) / max(duration_minutes, 1e-9), 4
            ),
            "metrics": {
                name: metric for name, metric in zip(class_ids, metrics, strict=True)
            },
        }
    return {"windows": int(len(probabilities)), "conditions": result}


def main() -> None:
    parser = argparse.ArgumentParser(description="评估非鸟分类头在噪声和设备模拟下的表现")
    parser.add_argument("cache", type=Path)
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/nonbird/stress_report.json"))
    args = parser.parse_args()
    cache = load_embedding_cache(args.cache)
    metadata = json.loads((args.model_dir / "metadata.json").read_text(encoding="utf-8"))
    class_ids = tuple(str(item) for item in cache["class_ids"])
    if tuple(metadata["class_ids"]) != class_ids:
        raise ValueError("模型与压力测试缓存的类别顺序不一致")
    model = tf.keras.models.load_model(args.model_dir / "classifier.h5", compile=False)
    probabilities = sigmoid(model.predict(cache["features"], verbose=0))
    thresholds = np.asarray([metadata["thresholds"][item] for item in class_ids])
    report = robustness_report(cache, probabilities, thresholds)
    report["model_id"] = metadata["model_id"]
    report["model_version"] = metadata["version"]
    write_json(args.output, report)
    print(f"saved robustness report to {args.output}")


if __name__ == "__main__":
    main()
