from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.rejection import build_embedding_reference
from ml.nonbird.config import load_nonbird_config
from ml.nonbird.training import find_precision_thresholds, load_embedding_cache, sigmoid, write_json


def main() -> None:
    parser = argparse.ArgumentParser(description="校准非鸟分类头阈值与未知声拒识参数")
    parser.add_argument("cache", type=Path)
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--minimum-precision", type=float, default=0.9)
    parser.add_argument("--version")
    parser.add_argument("--config", type=Path)
    args = parser.parse_args()
    cache = load_embedding_cache(args.cache)
    metadata_path = args.model_dir / "metadata.json"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    config = load_nonbird_config(args.config) if args.config else load_nonbird_config()
    class_ids = tuple(str(item) for item in cache["class_ids"])
    if tuple(metadata["class_ids"]) != class_ids:
        raise ValueError("模型与嵌入缓存类别不一致")
    train = cache["splits"] == "train"
    validation = cache["splits"] == "validation"
    model = tf.keras.models.load_model(args.model_dir / "classifier.h5", compile=False)
    probabilities = sigmoid(model.predict(cache["features"][validation], verbose=0))
    thresholds, metrics = find_precision_thresholds(
        cache["targets"][validation],
        probabilities,
        minimum_precision=args.minimum_precision,
    )
    metadata["thresholds"] = {
        class_id: float(threshold)
        for class_id, threshold in zip(class_ids, thresholds, strict=True)
    }
    metadata["version"] = args.version or config.version
    metadata["validation_metrics"] = {
        class_id: metric for class_id, metric in zip(class_ids, metrics, strict=True)
    }
    metadata["rejection"] = {
        "background_margin": 0.05,
        "min_top_margin": 0.0,
        "min_supporting_windows": 2,
        "short_clip_threshold_excess": 0.1,
        "max_window_gap_seconds": 0.15,
    }
    metadata["embedding_reference"] = build_embedding_reference(
        cache["features"][train],
        cache["targets"][train],
        cache["features"][validation],
        cache["targets"][validation],
        class_ids,
    )
    metadata["operating_point"] = {
        "objective": "minimum_precision",
        "minimum_precision": args.minimum_precision,
        "calibration_split": "validation",
    }
    write_json(metadata_path, metadata)
    print(f"calibrated rejection metadata at {metadata_path}")


if __name__ == "__main__":
    main()
