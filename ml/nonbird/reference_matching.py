from __future__ import annotations

from typing import Any

import numpy as np


def normalized_rows(values: np.ndarray) -> np.ndarray:
    values = values.astype(np.float32)
    norms = np.linalg.norm(values, axis=1, keepdims=True)
    return values / np.maximum(norms, 1e-8)


def build_official_reference_gallery(
    *,
    features: np.ndarray,
    targets: np.ndarray,
    groups: np.ndarray,
    class_ids: tuple[str, ...],
    target_class_ids: tuple[str, ...],
    minimum_similarity: float = 0.78,
    negative_quantile: float = 0.995,
    threshold_margin: float = 0.02,
) -> dict[str, Any]:
    """Build one normalized prototype per independent official source.

    The gallery is supporting evidence for runtime inference. It must never be
    enabled while reporting performance on the same official recordings.
    """
    if features.ndim != 2 or targets.shape != (len(features), len(class_ids)):
        raise ValueError("reference features and targets have incompatible shapes")
    if len(groups) != len(features):
        raise ValueError("reference groups do not match features")
    normalized = normalized_rows(features)
    class_index = {name: index for index, name in enumerate(class_ids)}
    classes: dict[str, Any] = {}
    all_prototypes: dict[str, np.ndarray] = {}
    for class_id in target_class_ids:
        index = class_index[class_id]
        positive = targets[:, index].astype(bool)
        prototypes: list[np.ndarray] = []
        source_ids: list[str] = []
        for group in sorted({str(value) for value in groups[positive]}):
            selected = normalized[np.logical_and(positive, groups == group)]
            if not len(selected):
                continue
            centroid = selected.mean(axis=0)
            centroid /= max(float(np.linalg.norm(centroid)), 1e-8)
            prototypes.append(centroid.astype(np.float32))
            source_ids.append(group)
        if not prototypes:
            continue
        all_prototypes[class_id] = np.stack(prototypes)
        classes[class_id] = {
            "source_count": len(prototypes),
            "source_ids": source_ids,
            "prototypes": np.round(np.stack(prototypes), 7).tolist(),
        }

    for class_id, prototypes in all_prototypes.items():
        index = class_index[class_id]
        negative_features = normalized[~targets[:, index].astype(bool)]
        negative_scores = (
            negative_features @ prototypes.T
            if len(negative_features)
            else np.empty((0, len(prototypes)), dtype=np.float32)
        )
        observed_negative = (
            float(np.quantile(negative_scores.max(axis=1), negative_quantile))
            if negative_scores.shape[1]
            else -1.0
        )
        threshold = min(0.98, max(minimum_similarity, observed_negative + threshold_margin))
        classes[class_id]["minimum_similarity"] = round(threshold, 4)

    return {
        "enabled": True,
        "source": "organizer_provided_standard_sounds",
        "role": "supporting_evidence_only",
        "warning": "Disable this gallery when evaluating the organizer recordings used to build it.",
        "minimum_classifier_probability": 0.25,
        "minimum_top_margin": 0.03,
        "classes": classes,
    }


def reference_similarity_scores(
    features: np.ndarray,
    class_ids: tuple[str, ...],
    metadata: dict[str, Any],
) -> np.ndarray:
    """Return maximum reference cosine similarity per window and class."""
    result = np.full((len(features), len(class_ids)), -1.0, dtype=np.float32)
    gallery = metadata.get("official_reference_matching") or {}
    if not gallery.get("enabled"):
        return result
    normalized = normalized_rows(features)
    rows = gallery.get("classes") or {}
    for index, class_id in enumerate(class_ids):
        prototypes = np.asarray(
            (rows.get(class_id) or {}).get("prototypes", []), dtype=np.float32
        )
        if prototypes.ndim != 2 or prototypes.shape[1:] != (features.shape[1],):
            continue
        result[:, index] = (normalized @ normalized_rows(prototypes).T).max(axis=1)
    return result


def reference_support_mask(
    *,
    features: np.ndarray,
    probabilities: np.ndarray,
    class_ids: tuple[str, ...],
    thresholds: np.ndarray,
    metadata: dict[str, Any],
) -> np.ndarray:
    """Return conservative reference support without replacing the classifier."""
    gallery = metadata.get("official_reference_matching") or {}
    supported = np.zeros_like(probabilities, dtype=bool)
    if not gallery.get("enabled"):
        return supported
    scores = reference_similarity_scores(features, class_ids, metadata)
    minimum_probability = float(gallery.get("minimum_classifier_probability", 0.25))
    minimum_margin = float(gallery.get("minimum_top_margin", 0.03))
    class_rows = gallery.get("classes") or {}
    for index, class_id in enumerate(class_ids):
        row = class_rows.get(class_id) or {}
        if not row:
            continue
        other = np.delete(scores, index, axis=1)
        runner_up = other.max(axis=1) if other.shape[1] else -1.0
        similarity_threshold = float(row.get("minimum_similarity", 1.0))
        # Reference evidence can recover a conservative near-threshold classifier
        # result, but can never identify a class on similarity alone.
        classifier_floor = np.minimum(thresholds[index], minimum_probability)
        supported[:, index] = np.logical_and.reduce(
            (
                probabilities[:, index] >= classifier_floor,
                scores[:, index] >= similarity_threshold,
                scores[:, index] - runner_up >= minimum_margin,
            )
        )
    return supported
