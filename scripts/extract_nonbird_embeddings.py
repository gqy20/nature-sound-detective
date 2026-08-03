from __future__ import annotations

import argparse
from pathlib import Path
import sys

import birdnet
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config
from ml.nonbird.dataset import load_manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="提取杭州非鸟训练集的 BirdNET embeddings")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/nonbird/embeddings.npz"))
    parser.add_argument("--overlap", type=float, default=0.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_nonbird_config()
    rows = load_manifest(args.manifest, config)
    model = birdnet.load("acoustic", "2.4", "tf")
    features: list[np.ndarray] = []
    targets: list[np.ndarray] = []
    splits: list[str] = []
    groups: list[str] = []
    paths: list[str] = []
    starts: list[float] = []
    ends: list[float] = []
    class_index = {name: index for index, name in enumerate(config.class_ids)}

    for row in rows:
        encoded = model.encode(row.audio_path, overlap_duration_s=args.overlap)
        for value in encoded.to_dataframe().to_dict(orient="records"):
            start = float(value["start_time"])
            end = float(value["end_time"])
            if not row.accepts_window(start, end):
                continue
            target = np.zeros(len(config.classes), dtype=np.float32)
            for label in row.labels:
                target[class_index[label]] = 1.0
            features.append(np.asarray(value["embedding"], dtype=np.float32))
            targets.append(target)
            splits.append(row.split)
            groups.append(row.split_group)
            paths.append(str(row.audio_path))
            starts.append(start)
            ends.append(end)
    if not features:
        raise RuntimeError("没有生成任何 embedding，请检查有效时间段")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        args.output,
        features=np.stack(features),
        targets=np.stack(targets),
        splits=np.asarray(splits),
        groups=np.asarray(groups),
        audio_paths=np.asarray(paths),
        start_seconds=np.asarray(starts, dtype=np.float32),
        end_seconds=np.asarray(ends, dtype=np.float32),
        class_ids=np.asarray(config.class_ids),
    )
    print(f"saved {len(features)} embeddings to {args.output}")


if __name__ == "__main__":
    main()
