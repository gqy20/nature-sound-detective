from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np
import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config
from ml.nonbird.training import (
    apply_threshold_floors,
    build_classifier,
    find_precision_thresholds,
    load_embedding_cache,
    missing_positive_coverage,
    metrics_at_thresholds,
    positive_class_weights,
    sigmoid,
    weighted_binary_crossentropy,
    write_json,
)
from ml.nonbird.rejection import build_embedding_reference


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="训练杭州非鸟多标签分类头")
    parser.add_argument("cache", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/nonbird/model"))
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--config", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tf.keras.utils.set_random_seed(20260803)
    config = load_nonbird_config(args.config) if args.config else load_nonbird_config()
    cache = load_embedding_cache(args.cache)
    cache_classes = tuple(str(item) for item in cache["class_ids"])
    if cache_classes != config.class_ids:
        raise ValueError("embedding cache 类别顺序与当前配置不一致")
    missing = missing_positive_coverage(
        cache["targets"], cache["splits"], cache_classes, ("train", "validation")
    )
    if missing:
        raise ValueError(f"训练/验证集缺少正样本: {missing}")
    train_mask = cache["splits"] == "train"
    validation_mask = cache["splits"] == "validation"
    if not train_mask.any() or not validation_mask.any():
        raise ValueError("训练集和验证集都必须至少包含一个窗口")
    x_train = cache["features"][train_mask].astype(np.float32)
    y_train = cache["targets"][train_mask].astype(np.float32)
    x_validation = cache["features"][validation_mask].astype(np.float32)
    y_validation = cache["targets"][validation_mask].astype(np.float32)
    pos_weights = positive_class_weights(y_train)
    model = build_classifier(x_train.shape[1], y_train.shape[1])
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=weighted_binary_crossentropy(pos_weights),
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model.fit(
        x_train,
        y_train,
        validation_data=(x_validation, y_validation),
        epochs=args.epochs,
        batch_size=args.batch_size,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_loss", patience=7, restore_best_weights=True
            )
        ],
        verbose=2,
    )
    model_path = args.output_dir / "classifier.h5"
    model.save(model_path, include_optimizer=False)
    probabilities = sigmoid(model.predict(x_validation, verbose=0))
    thresholds, metrics = find_precision_thresholds(y_validation, probabilities)
    thresholds = apply_threshold_floors(
        thresholds,
        np.asarray(
            [
                item.default_threshold if item.status == "experimental" else 0.0
                for item in config.classes
            ],
            dtype=np.float32,
        ),
    )
    metrics = metrics_at_thresholds(y_validation, probabilities, thresholds)
    embedding_reference = build_embedding_reference(
        x_train,
        y_train,
        x_validation,
        y_validation,
        config.class_ids,
    )
    write_json(
        args.output_dir / "metadata.json",
        {
            "model_id": config.model_id,
            "version": config.version,
            "embedding_model": "BirdNET acoustic 2.4",
            "embedding_dim": int(x_train.shape[1]),
            "class_ids": list(config.class_ids),
            "thresholds": {
                class_id: float(threshold)
                for class_id, threshold in zip(config.class_ids, thresholds, strict=True)
            },
            "validation_metrics": {
                class_id: metric
                for class_id, metric in zip(config.class_ids, metrics, strict=True)
            },
            "rejection": {
                "background_margin": 0.05,
                "min_top_margin": 0.0,
                "min_supporting_windows": 2,
                "short_clip_threshold_excess": 0.1,
                "max_window_gap_seconds": 0.15,
            },
            "embedding_reference": embedding_reference,
            "positive_class_weights": pos_weights.tolist(),
            "train_windows": int(train_mask.sum()),
            "validation_windows": int(validation_mask.sum()),
            "label_policies": sorted(
                {str(item) for item in cache.get("review_statuses", np.asarray([]))}
            ),
        },
    )
    print(f"saved classifier to {model_path}")


if __name__ == "__main__":
    main()
