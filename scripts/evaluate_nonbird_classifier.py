from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np
import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.training import (
    load_embedding_cache,
    metrics_at_thresholds,
    missing_positive_coverage,
    sigmoid,
    write_json,
)
from ml.nonbird.rejection import accepted_window_mask


def main() -> None:
    parser = argparse.ArgumentParser(description="评估杭州非鸟分类头")
    parser.add_argument("cache", type=Path)
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/nonbird/test_report.json"))
    args = parser.parse_args()
    cache = load_embedding_cache(args.cache)
    metadata = json.loads((args.model_dir / "metadata.json").read_text(encoding="utf-8"))
    class_ids = tuple(str(item) for item in cache["class_ids"])
    if tuple(metadata["class_ids"]) != class_ids:
        raise ValueError("模型与缓存的类别顺序不一致")
    missing = missing_positive_coverage(
        cache["targets"], cache["splits"], class_ids, ("test",)
    )
    if missing:
        raise ValueError(f"测试集缺少正样本: {missing}")
    test_mask = cache["splits"] == "test"
    if not test_mask.any():
        raise ValueError("缓存中没有测试窗口")
    model = tf.keras.models.load_model(args.model_dir / "classifier.h5", compile=False)
    probabilities = sigmoid(model.predict(cache["features"][test_mask], verbose=0))
    thresholds = np.asarray([metadata["thresholds"][item] for item in class_ids])
    test_features = cache["features"][test_mask]
    accepted = accepted_window_mask(
        features=test_features,
        probabilities=probabilities,
        groups=cache.get("audio_paths", cache["groups"])[test_mask],
        starts=cache["start_seconds"][test_mask],
        ends=cache["end_seconds"][test_mask],
        class_ids=class_ids,
        thresholds=thresholds,
        metadata=metadata,
    )
    metrics = metrics_at_thresholds(
        cache["targets"][test_mask],
        accepted.astype(np.float32),
        np.full(len(class_ids), 0.5),
    )
    write_json(
        args.output,
        {
            "test_windows": int(test_mask.sum()),
            "label_policies": metadata.get("label_policies", []),
            "rejection_applied": bool(metadata.get("rejection")),
            "metrics": {name: value for name, value in zip(class_ids, metrics, strict=True)},
        },
    )
    print(f"saved report to {args.output}")


if __name__ == "__main__":
    main()
