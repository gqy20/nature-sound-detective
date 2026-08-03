from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np


@dataclass(frozen=True)
class RejectionPolicy:
    background_margin: float = 0.05
    min_top_margin: float = 0.0
    min_supporting_windows: int = 2
    short_clip_threshold_excess: float = 0.1
    max_window_gap_seconds: float = 0.15

    @classmethod
    def from_metadata(cls, metadata: dict[str, Any]) -> "RejectionPolicy":
        value = metadata.get("rejection") or {}
        return cls(
            background_margin=float(value.get("background_margin", 0.05)),
            min_top_margin=float(value.get("min_top_margin", 0.0)),
            min_supporting_windows=int(value.get("min_supporting_windows", 2)),
            short_clip_threshold_excess=float(
                value.get("short_clip_threshold_excess", 0.1)
            ),
            max_window_gap_seconds=float(value.get("max_window_gap_seconds", 0.15)),
        )


def normalized_rows(values: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(values, axis=1, keepdims=True)
    return values / np.maximum(norms, 1e-8)


def build_embedding_reference(
    features: np.ndarray,
    targets: np.ndarray,
    validation_features: np.ndarray,
    validation_targets: np.ndarray,
    class_ids: tuple[str, ...],
) -> dict[str, dict[str, Any]]:
    normalized_train = normalized_rows(features.astype(np.float32))
    normalized_validation = normalized_rows(validation_features.astype(np.float32))
    result: dict[str, dict[str, Any]] = {}
    for index, class_id in enumerate(class_ids):
        selected = normalized_train[targets[:, index].astype(bool)]
        if not len(selected):
            raise ValueError(f"训练集缺少 {class_id} 嵌入")
        centroid = selected.mean(axis=0)
        centroid = centroid / max(float(np.linalg.norm(centroid)), 1e-8)
        validation_selected = normalized_validation[validation_targets[:, index].astype(bool)]
        similarities = validation_selected @ centroid
        floor = float(np.quantile(similarities, 0.02)) if len(similarities) else -1.0
        result[class_id] = {
            "centroid": np.round(centroid, 7).tolist(),
            "min_cosine_similarity": round(max(-1.0, floor - 0.02), 4),
        }
    return result


def accepted_window_mask(
    *,
    features: np.ndarray,
    probabilities: np.ndarray,
    groups: np.ndarray,
    starts: np.ndarray,
    ends: np.ndarray,
    class_ids: tuple[str, ...],
    thresholds: np.ndarray,
    metadata: dict[str, Any],
) -> np.ndarray:
    policy = RejectionPolicy.from_metadata(metadata)
    accepted = probabilities >= thresholds
    background_index = class_ids.index("background") if "background" in class_ids else None
    nonbackground = [index for index, item in enumerate(class_ids) if item != "background"]
    reference = metadata.get("embedding_reference") or {}
    normalized = normalized_rows(features.astype(np.float32))
    for class_index in nonbackground:
        competitors = [index for index in nonbackground if index != class_index]
        if competitors and policy.min_top_margin > 0:
            runner_up = probabilities[:, competitors].max(axis=1)
            accepted[:, class_index] &= (
                probabilities[:, class_index] - runner_up >= policy.min_top_margin
            )
        if background_index is not None:
            accepted[:, class_index] &= (
                probabilities[:, class_index] - probabilities[:, background_index]
                >= policy.background_margin
            )
        class_reference = reference.get(class_ids[class_index]) or {}
        centroid = np.asarray(class_reference.get("centroid", []), dtype=np.float32)
        if centroid.shape == (features.shape[1],):
            floor = float(class_reference.get("min_cosine_similarity", -1.0))
            accepted[:, class_index] &= normalized @ centroid >= floor
    if background_index is not None:
        accepted[:, background_index] = probabilities[:, background_index] >= thresholds[background_index]

    for group in np.unique(groups):
        indexes = np.flatnonzero(groups == group)
        indexes = indexes[np.argsort(starts[indexes])]
        for class_index in nonbackground:
            active = [int(index) for index in indexes if accepted[index, class_index]]
            keep: set[int] = set()
            run: list[int] = []
            for index in active:
                if run and starts[index] > ends[run[-1]] + policy.max_window_gap_seconds:
                    if len(run) >= policy.min_supporting_windows:
                        keep.update(run)
                    elif len(run) == 1 and probabilities[run[0], class_index] >= (
                        thresholds[class_index] + policy.short_clip_threshold_excess
                    ):
                        keep.update(run)
                    run = []
                run.append(index)
            if len(run) >= policy.min_supporting_windows:
                keep.update(run)
            elif len(run) == 1 and probabilities[run[0], class_index] >= (
                    thresholds[class_index] + policy.short_clip_threshold_excess
            ):
                keep.update(run)
            for index in indexes:
                accepted[index, class_index] = int(index) in keep
    return accepted
