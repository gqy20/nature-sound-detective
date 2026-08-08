import numpy as np

from ml.nonbird.rejection import accepted_window_mask, build_embedding_reference
from ml.nonbird.reference_matching import (
    build_official_reference_gallery,
    reference_similarity_scores,
)
from ml.nonbird.training import find_precision_thresholds


def _metadata():
    return {
        "rejection": {
            "background_margin": 0.05,
            "min_top_margin": 0.08,
            "min_supporting_windows": 2,
            "short_clip_threshold_excess": 0.1,
            "max_window_gap_seconds": 0.15,
        }
    }


def test_rejection_requires_temporal_support_and_margin():
    probabilities = np.asarray(
        [[0.9, 0.1, 0.1], [0.91, 0.1, 0.1], [0.7, 0.68, 0.1]], dtype=np.float32
    )
    accepted = accepted_window_mask(
        features=np.ones((3, 2), dtype=np.float32),
        probabilities=probabilities,
        groups=np.asarray(["a", "a", "a"]),
        starts=np.asarray([0.0, 3.0, 6.0]),
        ends=np.asarray([3.0, 6.0, 9.0]),
        class_ids=("frog", "insect", "background"),
        thresholds=np.asarray([0.5, 0.5, 0.5]),
        metadata=_metadata(),
    )
    assert accepted[:, 0].tolist() == [True, True, False]


def test_background_dominance_rejects_species():
    accepted = accepted_window_mask(
        features=np.ones((1, 2), dtype=np.float32),
        probabilities=np.asarray([[0.95, 0.2, 0.94]], dtype=np.float32),
        groups=np.asarray(["a"]),
        starts=np.asarray([0.0]),
        ends=np.asarray([3.0]),
        class_ids=("frog", "insect", "background"),
        thresholds=np.asarray([0.5, 0.5, 0.5]),
        metadata=_metadata(),
    )
    assert not accepted[0, 0]


def test_embedding_reference_rejects_distant_embedding():
    reference = build_embedding_reference(
        np.asarray([[1.0, 0.0], [0.9, 0.1]], dtype=np.float32),
        np.asarray([[1], [1]], dtype=np.float32),
        np.asarray([[1.0, 0.0]], dtype=np.float32),
        np.asarray([[1]], dtype=np.float32),
        ("frog",),
    )
    metadata = _metadata()
    metadata["embedding_reference"] = reference
    accepted = accepted_window_mask(
        features=np.asarray([[0.0, 1.0]], dtype=np.float32),
        probabilities=np.asarray([[0.9]], dtype=np.float32),
        groups=np.asarray(["a"]),
        starts=np.asarray([0.0]),
        ends=np.asarray([3.0]),
        class_ids=("frog",),
        thresholds=np.asarray([0.5]),
        metadata=metadata,
    )
    assert not accepted[0, 0]


def test_precision_threshold_prefers_precision_target():
    truth = np.asarray([[1], [1], [0], [0]], dtype=np.float32)
    probabilities = np.asarray([[0.9], [0.7], [0.65], [0.2]], dtype=np.float32)
    thresholds, metrics = find_precision_thresholds(truth, probabilities, minimum_precision=1.0)
    assert thresholds[0] > 0.65
    assert metrics[0]["precision"] == 1.0


def test_official_reference_is_supporting_evidence_and_can_be_disabled():
    features = np.asarray([[1.0, 0.0], [0.99, 0.01], [0.0, 1.0]], dtype=np.float32)
    targets = np.asarray([[1, 0], [1, 0], [0, 1]], dtype=np.float32)
    gallery = build_official_reference_gallery(
        features=features,
        targets=targets,
        groups=np.asarray(["frog-a", "frog-a", "insect-a"]),
        class_ids=("frog", "insect"),
        target_class_ids=("frog", "insect"),
        minimum_similarity=0.7,
    )
    metadata = _metadata()
    metadata["official_reference_matching"] = gallery
    probabilities = np.asarray([[0.4, 0.1], [0.42, 0.1]], dtype=np.float32)
    common = dict(
        features=features[:2],
        probabilities=probabilities,
        groups=np.asarray(["recording", "recording"]),
        starts=np.asarray([0.0, 3.0]),
        ends=np.asarray([3.0, 6.0]),
        class_ids=("frog", "insect"),
        thresholds=np.asarray([0.8, 0.8]),
        metadata=metadata,
    )
    assert accepted_window_mask(**common)[:, 0].tolist() == [True, True]
    assert not accepted_window_mask(
        **common, use_official_reference=False
    )[:, 0].any()
    scores = reference_similarity_scores(features[:2], ("frog", "insect"), metadata)
    assert np.all(scores[:, 0] > 0.99)
