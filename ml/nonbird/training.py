from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf


def build_classifier(embedding_dim: int, class_count: int) -> tf.keras.Model:
    return tf.keras.Sequential(
        [
            tf.keras.layers.Input(shape=(embedding_dim,), name="embedding"),
            tf.keras.layers.LayerNormalization(name="embedding_norm"),
            tf.keras.layers.Dense(256, activation="relu", name="hidden"),
            tf.keras.layers.Dropout(0.25, name="dropout"),
            tf.keras.layers.Dense(class_count, name="logits"),
        ],
        name="hangzhou_nonbird_classifier",
    )


def positive_class_weights(targets: np.ndarray) -> np.ndarray:
    positives = targets.sum(axis=0)
    negatives = targets.shape[0] - positives
    return np.clip(negatives / np.maximum(positives, 1), 1.0, 20.0).astype(np.float32)


def weighted_binary_crossentropy(pos_weights: np.ndarray):
    weights = tf.constant(pos_weights, dtype=tf.float32)

    def loss(y_true, logits):
        return tf.reduce_mean(
            tf.nn.weighted_cross_entropy_with_logits(
                labels=tf.cast(y_true, tf.float32),
                logits=logits,
                pos_weight=weights,
            )
        )

    return loss


def sigmoid(values: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(values, -30, 30)))


def find_best_thresholds(
    targets: np.ndarray,
    probabilities: np.ndarray,
    *,
    candidates: np.ndarray | None = None,
) -> tuple[np.ndarray, list[dict[str, float]]]:
    grid = candidates if candidates is not None else np.arange(0.1, 0.91, 0.05)
    thresholds = np.full(targets.shape[1], 0.5, dtype=np.float32)
    metrics: list[dict[str, float]] = []
    for class_index in range(targets.shape[1]):
        truth = targets[:, class_index].astype(bool)
        best = {"threshold": 0.5, "precision": 0.0, "recall": 0.0, "f1": -1.0}
        for threshold in grid:
            predicted = probabilities[:, class_index] >= threshold
            tp = int(np.logical_and(predicted, truth).sum())
            fp = int(np.logical_and(predicted, ~truth).sum())
            fn = int(np.logical_and(~predicted, truth).sum())
            precision = tp / (tp + fp) if tp + fp else 0.0
            recall = tp / (tp + fn) if tp + fn else 0.0
            f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
            if f1 > best["f1"] or (f1 == best["f1"] and threshold > best["threshold"]):
                best = {
                    "threshold": float(round(float(threshold), 4)),
                    "precision": round(precision, 4),
                    "recall": round(recall, 4),
                    "f1": round(f1, 4),
                }
        thresholds[class_index] = best["threshold"]
        metrics.append(best)
    return thresholds, metrics


def find_precision_thresholds(
    targets: np.ndarray,
    probabilities: np.ndarray,
    *,
    minimum_precision: float = 0.9,
    candidates: np.ndarray | None = None,
) -> tuple[np.ndarray, list[dict[str, float]]]:
    grid = candidates if candidates is not None else np.arange(0.1, 0.96, 0.05)
    f1_thresholds, f1_metrics = find_best_thresholds(
        targets, probabilities, candidates=grid
    )
    thresholds = f1_thresholds.copy()
    metrics = list(f1_metrics)
    for class_index in range(targets.shape[1]):
        truth = targets[:, class_index].astype(bool)
        eligible: list[dict[str, float]] = []
        for threshold in grid:
            predicted = probabilities[:, class_index] >= threshold
            tp = int(np.logical_and(predicted, truth).sum())
            fp = int(np.logical_and(predicted, ~truth).sum())
            fn = int(np.logical_and(~predicted, truth).sum())
            precision = tp / (tp + fp) if tp + fp else 0.0
            recall = tp / (tp + fn) if tp + fn else 0.0
            if precision >= minimum_precision and tp:
                f1 = 2 * precision * recall / (precision + recall) if recall else 0.0
                eligible.append(
                    {
                        "threshold": float(round(float(threshold), 4)),
                        "precision": round(precision, 4),
                        "recall": round(recall, 4),
                        "f1": round(f1, 4),
                    }
                )
        if eligible:
            best = max(eligible, key=lambda item: (item["recall"], item["f1"], -item["threshold"]))
            thresholds[class_index] = best["threshold"]
            metrics[class_index] = best
    return thresholds, metrics


def metrics_at_thresholds(
    targets: np.ndarray,
    probabilities: np.ndarray,
    thresholds: np.ndarray,
) -> list[dict[str, float]]:
    metrics: list[dict[str, float]] = []
    for class_index, threshold in enumerate(thresholds):
        truth = targets[:, class_index].astype(bool)
        predicted = probabilities[:, class_index] >= threshold
        tp = int(np.logical_and(predicted, truth).sum())
        fp = int(np.logical_and(predicted, ~truth).sum())
        fn = int(np.logical_and(~predicted, truth).sum())
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        metrics.append(
            {
                "threshold": round(float(threshold), 4),
                "precision": round(precision, 4),
                "recall": round(recall, 4),
                "f1": round(f1, 4),
            }
        )
    return metrics


def load_embedding_cache(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as value:
        required = {"features", "targets", "splits", "class_ids"}
        missing = required - set(value.files)
        if missing:
            raise ValueError(f"embedding cache 缺少字段: {sorted(missing)}")
        return {key: value[key] for key in value.files}


def missing_positive_coverage(
    targets: np.ndarray,
    splits: np.ndarray,
    class_ids: tuple[str, ...],
    required_splits: tuple[str, ...],
) -> list[str]:
    missing: list[str] = []
    for split in required_splits:
        split_targets = targets[splits == split]
        for index, class_id in enumerate(class_ids):
            if not len(split_targets) or not split_targets[:, index].any():
                missing.append(f"{split}:{class_id}")
    return missing


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
