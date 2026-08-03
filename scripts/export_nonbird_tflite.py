from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.config import load_nonbird_config


def main() -> None:
    parser = argparse.ArgumentParser(description="导出非鸟分类头 TFLite 和移动端元数据")
    parser.add_argument("model_dir", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/nonbird/export"))
    parser.add_argument("--install-mobile", action="store_true")
    args = parser.parse_args()
    metadata = json.loads((args.model_dir / "metadata.json").read_text(encoding="utf-8"))
    config = load_nonbird_config()
    model = tf.keras.models.load_model(args.model_dir / "classifier.h5", compile=False)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    model_bytes = converter.convert()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.output_dir / "nonbird.tflite"
    model_path.write_bytes(model_bytes)
    class_map = {item.taxon_id: item for item in config.classes}
    mobile_metadata = {
        "id": metadata["model_id"],
        "version": metadata["version"],
        "available": True,
        "input": {"type": "birdnet_embedding", "shape": [1, metadata["embedding_dim"]]},
        "output": {"type": "logits", "shape": [1, len(metadata["class_ids"])]},
        "birdnet_embedding_tensor_index": 545,
        "birdnet_embedding_tensor_name": "model/GLOBAL_AVG_POOL/Mean",
        "sha256": hashlib.sha256(model_bytes).hexdigest(),
        "classes": [
            {
                "output_index": index,
                "taxon_id": class_id,
                "category_id": class_map[class_id].category_id,
                "name_zh": class_map[class_id].name_zh,
                "scientific_name": class_map[class_id].scientific_name,
                "threshold": metadata["thresholds"][class_id],
            }
            for index, class_id in enumerate(metadata["class_ids"])
        ],
    }
    metadata_path = args.output_dir / "nonbird.json"
    metadata_path.write_text(
        json.dumps(mobile_metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if args.install_mobile:
        mobile_dir = Path("mobile/assets/models")
        mobile_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(model_path, mobile_dir / model_path.name)
        shutil.copy2(metadata_path, mobile_dir / metadata_path.name)
    print(f"exported {model_path} and {metadata_path}")


if __name__ == "__main__":
    main()
