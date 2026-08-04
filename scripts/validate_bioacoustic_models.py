from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import ROOT
from app.species_catalog import load_hangzhou_birdnet_catalog


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _shape(detail: dict[str, Any]) -> list[int]:
    return [int(value) for value in detail["shape"]]


def validate() -> dict[str, Any]:
    model_dir = ROOT / "mobile" / "assets" / "models"
    bird_metadata = json.loads((model_dir / "birdnet.json").read_text(encoding="utf-8"))
    bird_model = model_dir / "birdnet.tflite"
    bird_interpreter = tf.lite.Interpreter(model_path=str(bird_model))
    bird_inputs = bird_interpreter.get_input_details()
    bird_outputs = bird_interpreter.get_output_details()
    bird_catalog = load_hangzhou_birdnet_catalog()

    errors: list[str] = []
    if _sha256(bird_model) != bird_metadata["sha256"]:
        errors.append("BirdNET SHA-256 与元数据不一致")
    if len(bird_inputs) != 1 or _shape(bird_inputs[0]) != [1, 144000]:
        errors.append("BirdNET 输入必须为 [1, 144000]")
    output_shapes = [_shape(item) for item in bird_outputs]
    if output_shapes != [[1, 6522], [1, 1024]]:
        errors.append(f"BirdNET 输出应为分类与嵌入，实际为 {output_shapes}")
    if len(bird_catalog) != 200 or bird_metadata.get("candidate_count") != 200:
        errors.append("杭州 BirdNET 候选目录必须正好包含 200 种")

    nonbird_metadata = json.loads((model_dir / "nonbird.json").read_text(encoding="utf-8"))
    nonbird_installed = bool(nonbird_metadata.get("available"))
    nonbird_model = model_dir / "nonbird.tflite"
    if nonbird_installed:
        class_rows = nonbird_metadata.get("classes", [])
        exported_ids = {str(item["taxon_id"]) for item in class_rows}
        if not nonbird_model.is_file():
            errors.append("nonbird.json 标记可用，但 nonbird.tflite 不存在")
        else:
            interpreter = tf.lite.Interpreter(model_path=str(nonbird_model))
            input_shapes = [_shape(item) for item in interpreter.get_input_details()]
            output_shapes_nonbird = [_shape(item) for item in interpreter.get_output_details()]
            if input_shapes != [[1, 1024]]:
                errors.append(f"非鸟分类头输入应为 [1, 1024]，实际为 {input_shapes}")
            expected_output = [[1, len(exported_ids)]]
            if output_shapes_nonbird != expected_output:
                errors.append(f"非鸟分类头输出应为 {expected_output}，实际为 {output_shapes_nonbird}")
            if _sha256(nonbird_model) != nonbird_metadata.get("sha256"):
                errors.append("非鸟分类头 SHA-256 与元数据不一致")
        if not exported_ids or len(exported_ids) != len(class_rows):
            errors.append("非鸟分类头必须提供唯一的自描述类别目录")

    return {
        "ok": not errors,
        "errors": errors,
        "birdnet": {
            "candidate_count": len(bird_catalog),
            "input_shapes": [_shape(item) for item in bird_inputs],
            "output_shapes": output_shapes,
        },
        "nonbird": {
            "installed": nonbird_installed,
            "status": "ready" if nonbird_installed else "awaiting_reviewed_training_data",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="校验端侧生物声学模型及元数据契约")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = validate()
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    if not report["ok"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
