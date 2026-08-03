import numpy as np
import pytest

from ml.nonbird.config import load_nonbird_config
from ml.nonbird.dataset import load_manifest
from ml.nonbird.training import find_best_thresholds, positive_class_weights


def test_nonbird_config_has_stable_class_order():
    config = load_nonbird_config()
    assert config.class_ids == (
        "cryptotympana_atrata",
        "polypedates_braueri",
        "other_insect",
        "other_frog",
        "background",
    )
    assert config.sample_rate == 48000


def test_threshold_search_finds_separating_threshold():
    targets = np.asarray([[0], [0], [1], [1]], dtype=np.float32)
    probabilities = np.asarray([[0.05], [0.2], [0.7], [0.9]], dtype=np.float32)
    thresholds, metrics = find_best_thresholds(targets, probabilities)
    assert 0.2 < thresholds[0] <= 0.7
    assert metrics[0]["f1"] == 1.0


def test_positive_class_weights_upweight_rare_class():
    targets = np.asarray([[1, 0], [1, 0], [0, 0], [0, 1]], dtype=np.float32)
    weights = positive_class_weights(targets)
    assert weights.tolist() == [1.0, 3.0]


def test_manifest_ignores_pending_rows_and_loads_approved_rows(tmp_path):
    audio = tmp_path / "sample.wav"
    audio.write_bytes(b"RIFF")
    manifest = tmp_path / "manifest.csv"
    manifest.write_text(
        "audio_path,labels,split,split_group,review_status,start_seconds,end_seconds\n"
        "sample.wav,cryptotympana_atrata,train,source-a,approved,0,3\n"
        "sample.wav,background,test,source-b,pending,,\n",
        encoding="utf-8",
    )
    rows = load_manifest(manifest, load_nonbird_config())
    assert len(rows) == 1
    assert rows[0].labels == ("cryptotympana_atrata",)
    assert rows[0].accepts_window(0, 3)


def test_manifest_rejects_split_group_leakage(tmp_path):
    audio = tmp_path / "sample.wav"
    audio.write_bytes(b"RIFF")
    manifest = tmp_path / "manifest.csv"
    manifest.write_text(
        "audio_path,labels,split,split_group,review_status\n"
        "sample.wav,background,train,same-source,approved\n"
        "sample.wav,background,test,same-source,approved\n",
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="跨集合泄漏"):
        load_manifest(manifest, load_nonbird_config())
