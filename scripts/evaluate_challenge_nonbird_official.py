from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path
import sys

import numpy as np
import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.rejection import accepted_window_mask
from ml.nonbird.training import load_embedding_cache, sigmoid, write_json


def metrics(truth: np.ndarray, predicted: np.ndarray) -> dict[str, float | int]:
    tp = int(np.logical_and(truth, predicted).sum())
    fp = int(np.logical_and(~truth, predicted).sum())
    fn = int(np.logical_and(truth, ~predicted).sum())
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "positive_windows": int(truth.sum()),
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="单独评估主办方虫蛙标准声")
    parser.add_argument("cache", type=Path)
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    cache = load_embedding_cache(args.cache)
    metadata = json.loads((args.model_dir / "metadata.json").read_text(encoding="utf-8"))
    class_ids = tuple(str(value) for value in cache["class_ids"])
    official = cache["review_statuses"] == "official_reference"
    if not official.any():
        raise ValueError("缓存中没有official_reference窗口")
    model = tf.keras.models.load_model(args.model_dir / "classifier.h5", compile=False)
    features = cache["features"][official]
    probabilities = sigmoid(model.predict(features, verbose=0))
    thresholds = np.asarray([metadata["thresholds"][item] for item in class_ids])
    accepted = accepted_window_mask(
        features=features,
        probabilities=probabilities,
        groups=cache["groups"][official],
        starts=cache["start_seconds"][official],
        ends=cache["end_seconds"][official],
        class_ids=class_ids,
        thresholds=thresholds,
        metadata=metadata,
    )
    target_ids = class_ids[:9]
    per_class = {
        class_id: metrics(
            cache["targets"][official, index].astype(bool), accepted[:, index]
        )
        for index, class_id in enumerate(target_ids)
    }
    group_indexes: dict[str, list[int]] = defaultdict(list)
    for index, group in enumerate(cache["groups"][official]):
        group_indexes[str(group)].append(index)
    source_hits: list[bool] = []
    for indexes in group_indexes.values():
        truth = cache["targets"][official][indexes].max(axis=0).astype(bool)
        predicted = accepted[indexes].max(axis=0)
        expected = np.flatnonzero(truth[:9])
        source_hits.append(bool(len(expected) and predicted[expected].any()))
    report = {
        "evaluation": "organizer-provided non-bird standard sounds held out from training",
        "warning": "每类仅1到2个源录音，结果只能作为覆盖检查，不能视为正式泛化准确率。",
        "official_sources": len(group_indexes),
        "official_windows": int(official.sum()),
        "source_recall": round(sum(source_hits) / len(source_hits), 4),
        "per_class": per_class,
        "macro_f1": round(sum(value["f1"] for value in per_class.values()) / len(per_class), 4),
    }
    write_json(args.output, report)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
