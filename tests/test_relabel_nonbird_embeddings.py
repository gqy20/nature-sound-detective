from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from ml.nonbird.config import load_nonbird_config
from scripts.relabel_nonbird_embeddings import relabel_cache


def test_relabel_cache_reuses_features_and_updates_targets(tmp_path: Path):
    audio = tmp_path / "tree-frog.wav"
    audio.write_bytes(b"RIFF")
    config = load_nonbird_config()
    cache = tmp_path / "old.npz"
    features = np.ones((2, 1024), dtype=np.float32)
    np.savez_compressed(
        cache,
        features=features,
        targets=np.zeros((2, 5), dtype=np.float32),
        splits=np.asarray(["train", "train"]),
        groups=np.asarray(["old", "old"]),
        audio_paths=np.asarray([str(audio), str(audio)]),
        start_seconds=np.asarray([0.0, 3.0], dtype=np.float32),
        end_seconds=np.asarray([3.0, 6.0], dtype=np.float32),
        review_statuses=np.asarray(["source_curated", "source_curated"]),
        class_ids=np.asarray(["old"]),
    )
    manifest = tmp_path / "manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=(
                "audio_path",
                "labels",
                "split",
                "split_group",
                "review_status",
                "start_seconds",
                "end_seconds",
            ),
        )
        writer.writeheader()
        writer.writerow(
            {
                "audio_path": audio.name,
                "labels": "hyla_chinensis",
                "split": "validation",
                "split_group": "tree-frog-observation",
                "review_status": "source_curated",
                "start_seconds": "",
                "end_seconds": "",
            }
        )

    output = tmp_path / "new.npz"
    assert relabel_cache(cache, manifest, output) == 2

    with np.load(output, allow_pickle=False) as value:
        index = list(value["class_ids"]).index("hyla_chinensis")
        assert np.array_equal(value["features"], features)
        assert value["targets"][:, index].tolist() == [1.0, 1.0]
        assert value["splits"].tolist() == ["validation", "validation"]
        assert value["groups"].tolist() == [
            "tree-frog-observation",
            "tree-frog-observation",
        ]
        assert value["class_ids"].tolist() == list(config.class_ids)
