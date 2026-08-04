from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


LEGACY_MAP = {
    "cryptotympana_atrata": "cryptotympana_atrata",
    "hyla_chinensis": "other_frog",
    "kaloula_borealis": "other_frog",
    "other_frog": "other_frog",
    "other_insect": "other_insect",
    "pelophylax_nigromaculatus": "pelophylax_nigromaculatus",
    "planopleura_kaempferi": "other_insect",
    "polypedates_braueri": "other_frog",
    "streeyola_mongolica": "streeyola_mongolica",
    "background": "background",
}


def load(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as value:
        return {key: value[key] for key in value.files}


def remap_targets(cache: dict[str, np.ndarray], class_ids: tuple[str, ...]) -> np.ndarray:
    output = np.zeros((len(cache["targets"]), len(class_ids)), dtype=np.float32)
    destination = {class_id: index for index, class_id in enumerate(class_ids)}
    for old_index, value in enumerate(cache["class_ids"]):
        mapped = LEGACY_MAP.get(str(value))
        if mapped is not None:
            output[:, destination[mapped]] = np.maximum(
                output[:, destination[mapped]], cache["targets"][:, old_index]
            )
    return output


def optional_text(cache: dict[str, np.ndarray], key: str, default: str) -> np.ndarray:
    return cache.get(key, np.asarray([default] * len(cache["features"])))


def main() -> None:
    parser = argparse.ArgumentParser(description="复用旧嵌入并合并挑战赛新增虫蛙嵌入")
    parser.add_argument("legacy", type=Path)
    parser.add_argument("challenge", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    legacy = load(args.legacy)
    challenge = load(args.challenge)
    class_ids = tuple(str(value) for value in challenge["class_ids"])
    legacy_targets = remap_targets(legacy, class_ids)

    challenge_keys = {
        (str(group), round(float(start), 3), round(float(end), 3))
        for group, start, end in zip(
            challenge["groups"],
            challenge["start_seconds"],
            challenge["end_seconds"],
            strict=True,
        )
    }
    keep = np.asarray(
        [
            (str(group), round(float(start), 3), round(float(end), 3)) not in challenge_keys
            for group, start, end in zip(
                legacy["groups"], legacy["start_seconds"], legacy["end_seconds"], strict=True
            )
        ],
        dtype=bool,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        args.output,
        features=np.concatenate([challenge["features"], legacy["features"][keep]]),
        targets=np.concatenate([challenge["targets"], legacy_targets[keep]]),
        splits=np.concatenate([challenge["splits"], legacy["splits"][keep]]),
        groups=np.concatenate([challenge["groups"], legacy["groups"][keep]]),
        audio_paths=np.concatenate([challenge["audio_paths"], legacy["audio_paths"][keep]]),
        start_seconds=np.concatenate([challenge["start_seconds"], legacy["start_seconds"][keep]]),
        end_seconds=np.concatenate([challenge["end_seconds"], legacy["end_seconds"][keep]]),
        review_statuses=np.concatenate(
            [
                optional_text(challenge, "review_statuses", "source_curated"),
                optional_text(legacy, "review_statuses", "source_curated")[keep],
            ]
        ),
        conditions=np.concatenate(
            [
                optional_text(challenge, "conditions", "clean"),
                optional_text(legacy, "conditions", "clean")[keep],
            ]
        ),
        class_ids=np.asarray(class_ids),
    )
    print(
        f"combined challenge={len(challenge['features'])} "
        f"legacy_kept={int(keep.sum())} output={args.output}"
    )


if __name__ == "__main__":
    main()
