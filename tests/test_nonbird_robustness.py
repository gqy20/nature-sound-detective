from pathlib import Path

import numpy as np

from ml.nonbird.robustness import mix_at_snr, read_pcm16_mono, write_pcm16_mono
from scripts.evaluate_nonbird_robustness import robustness_report


def test_mix_at_snr_preserves_shape_and_requested_ratio():
    rng = np.random.default_rng(7)
    target = rng.normal(0, 0.05, 48000).astype(np.float32)
    noise = rng.normal(0, 0.05, 24000).astype(np.float32)
    mixed = mix_at_snr(target, noise, 10, rng=np.random.default_rng(8))
    assert mixed.shape == target.shape
    assert np.max(np.abs(mixed)) <= 0.98


def test_pcm_round_trip(tmp_path: Path):
    path = tmp_path / "audio.wav"
    values = np.linspace(-0.5, 0.5, 1000, dtype=np.float32)
    write_pcm16_mono(path, values)
    restored = read_pcm16_mono(path)
    assert np.allclose(restored, values, atol=1 / 32768)


def test_robustness_report_counts_background_false_positives():
    cache = {
        "features": np.zeros((2, 2), dtype=np.float32),
        "targets": np.asarray([[0, 1], [1, 0]], dtype=np.float32),
        "class_ids": np.asarray(["frog", "background"]),
        "conditions": np.asarray(["background_clean", "snr_0"]),
    }
    report = robustness_report(
        cache,
        probabilities=np.asarray([[0.8, 0.9], [0.8, 0.1]], dtype=np.float32),
        thresholds=np.asarray([0.5, 0.5], dtype=np.float32),
    )
    assert report["conditions"]["background_clean"]["false_positive_rate"] == 1.0
    assert report["conditions"]["snr_0"]["false_positive_rate"] == 0.0
