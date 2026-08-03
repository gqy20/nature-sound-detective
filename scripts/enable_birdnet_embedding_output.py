from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import flatbuffers
from tensorflow.lite.python import schema_py_generated as schema


EMBEDDING_TENSOR_INDEX = 545
EMBEDDING_TENSOR_NAME = "model/GLOBAL_AVG_POOL/Mean"


def main() -> None:
    parser = argparse.ArgumentParser(description="为 BirdNET TFLite 增加显式 embedding 输出")
    parser.add_argument("model", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--metadata", type=Path)
    args = parser.parse_args()
    source = args.model.read_bytes()
    model = schema.ModelT.InitFromObj(schema.Model.GetRootAsModel(source, 0))
    subgraph = model.subgraphs[0]
    tensor = subgraph.tensors[EMBEDDING_TENSOR_INDEX]
    name = tensor.name.decode("utf-8") if isinstance(tensor.name, bytes) else tensor.name
    if name != EMBEDDING_TENSOR_NAME or list(tensor.shape) != [1, 1024]:
        raise ValueError(f"BirdNET embedding tensor changed: {name} {list(tensor.shape)}")
    if EMBEDDING_TENSOR_INDEX not in subgraph.outputs:
        subgraph.outputs = list(subgraph.outputs) + [EMBEDDING_TENSOR_INDEX]
    builder = flatbuffers.Builder(0)
    packed = model.Pack(builder)
    builder.Finish(packed, file_identifier=b"TFL3")
    output = args.output or args.model
    output.write_bytes(bytes(builder.Output()))
    if args.metadata:
        metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
        metadata["sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
        metadata["outputs"] = [
            {"index": 0, "name": "species_logits", "shape": [1, 6522]},
            {"index": 1, "name": "embedding", "shape": [1, 1024]},
        ]
        metadata["embedding_tensor_source_index"] = EMBEDDING_TENSOR_INDEX
        args.metadata.write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print(f"wrote dual-output BirdNET model to {output}")


if __name__ == "__main__":
    main()
