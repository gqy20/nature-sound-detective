from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config
from ml.nonbird.dataset import load_manifest
from ml.nonbird.training import load_embedding_cache


def relabel_cache(cache_path: Path, manifest_path: Path, output_path: Path) -> int:
    config = load_nonbird_config()
    cache = load_embedding_cache(cache_path)
    rows = load_manifest(manifest_path, config)
    rows_by_path = {str(row.audio_path.resolve()).casefold(): row for row in rows}
    if len(rows_by_path) != len(rows):
        raise ValueError("重标清单必须每个音频路径只包含一行")

    cached_paths = {str(Path(value).resolve()).casefold() for value in cache["audio_paths"]}
    missing_from_cache = sorted(set(rows_by_path) - cached_paths)
    missing_from_manifest = sorted(cached_paths - set(rows_by_path))
    if missing_from_cache or missing_from_manifest:
        raise ValueError(
            "embedding 与清单音频不一致: "
            f"cache_missing={len(missing_from_cache)} "
            f"manifest_missing={len(missing_from_manifest)}"
        )

    class_index = {class_id: index for index, class_id in enumerate(config.class_ids)}
    targets = np.zeros((len(cache["features"]), len(config.class_ids)), dtype=np.float32)
    splits: list[str] = []
    groups: list[str] = []
    review_statuses: list[str] = []
    for index, value in enumerate(cache["audio_paths"]):
        row = rows_by_path[str(Path(value).resolve()).casefold()]
        for label in row.labels:
            targets[index, class_index[label]] = 1.0
        splits.append(row.split)
        groups.append(row.split_group)
        review_statuses.append(row.review_status)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        key: value
        for key, value in cache.items()
        if key not in {"targets", "splits", "groups", "review_statuses", "class_ids"}
    }
    np.savez_compressed(
        output_path,
        **payload,
        targets=targets,
        splits=np.asarray(splits),
        groups=np.asarray(groups),
        review_statuses=np.asarray(review_statuses),
        class_ids=np.asarray(config.class_ids),
    )
    return len(targets)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="在音频不变时复用 BirdNET embedding 并更新非鸟标签"
    )
    parser.add_argument("cache", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    count = relabel_cache(args.cache, args.manifest, args.output)
    print(f"relabeled {count} embeddings to {args.output}")


if __name__ == "__main__":
    main()
