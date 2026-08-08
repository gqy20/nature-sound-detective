from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.reference_matching import build_official_reference_gallery
from ml.nonbird.training import load_embedding_cache, write_json


def main() -> None:
    parser = argparse.ArgumentParser(
        description="从主办方标准声构建独立的 BirdNET embedding 参考库"
    )
    parser.add_argument("cache", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--status", default="official_reference")
    args = parser.parse_args()

    cache = load_embedding_cache(args.cache)
    statuses = cache.get("review_statuses")
    if statuses is None:
        raise ValueError("embedding 缓存缺少 review_statuses")
    selected = statuses == args.status
    if not selected.any():
        raise ValueError(f"embedding 缓存没有 {args.status} 窗口")
    class_ids = tuple(str(value) for value in cache["class_ids"])
    target_ids = tuple(value for value in class_ids if value not in {
        "other_insect", "other_frog", "background"
    })
    gallery = build_official_reference_gallery(
        features=cache["features"][selected],
        targets=cache["targets"][selected],
        groups=cache["groups"][selected],
        class_ids=class_ids,
        target_class_ids=target_ids,
    )
    write_json(args.output, gallery)
    if args.metadata:
        metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
        if tuple(metadata["class_ids"]) != class_ids:
            raise ValueError("模型和参考库类别顺序不一致")
        metadata["official_reference_matching"] = gallery
        write_json(args.metadata, metadata)
    print(
        f"saved {len(gallery['classes'])} official reference classes to {args.output}"
    )


if __name__ == "__main__":
    main()
