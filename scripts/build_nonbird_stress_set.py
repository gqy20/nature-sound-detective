from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path
import random
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.nonbird.robustness import (
    apply_stress_condition,
    read_pcm16_mono,
    write_pcm16_mono,
)


DEFAULT_CONDITIONS = (
    "snr_-5",
    "snr_0",
    "snr_5",
    "snr_10",
    "snr_15",
    "quiet",
    "gain_db_-12",
    "gain_db_6",
    "shift_ms_750",
    "reverb",
    "phone_band",
    "resample_16000",
    "quantize_8bit",
)


def read_manifest(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def resolve_audio(manifest: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else (manifest.parent / path).resolve()


def build_stress_rows(
    manifest: Path,
    *,
    output_manifest: Path,
    audio_dir: Path,
    split: str,
    conditions: tuple[str, ...],
    max_recordings: int | None,
    seed: int,
    background_manifest: Path | None = None,
) -> list[dict[str, str]]:
    fields, rows = read_manifest(manifest)
    selected = [row for row in rows if row.get("split") == split]
    positives = [row for row in selected if row.get("labels") != "background"]
    backgrounds = [row for row in selected if row.get("labels") == "background"]
    background_source = manifest
    if background_manifest is not None:
        _, background_rows = read_manifest(background_manifest)
        backgrounds = [
            row
            for row in background_rows
            if row.get("split") == split and row.get("labels") == "background"
        ]
        background_source = background_manifest
    if not positives or not backgrounds:
        raise ValueError(f"{split} 集必须同时包含目标声与背景声")
    positives.sort(key=lambda row: row.get("source_recording_id", ""))
    if max_recordings is not None:
        positives = positives[:max_recordings]
    chooser = random.Random(seed)
    output_rows: list[dict[str, str]] = []
    audio_dir.mkdir(parents=True, exist_ok=True)
    for index, row in enumerate(positives):
        target = read_pcm16_mono(resolve_audio(manifest, row["audio_path"]))
        background = backgrounds[chooser.randrange(len(backgrounds))]
        noise = read_pcm16_mono(
            resolve_audio(background_source, background["audio_path"])
        )
        source_id = row.get("source_recording_id", f"row-{index}")
        noise_id = background.get("source_recording_id", "background")
        for condition in conditions:
            identity = f"{source_id}|{noise_id}|{condition}|{seed}"
            digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]
            destination = audio_dir / f"stress_{digest}.wav"
            if not destination.exists():
                rng_seed = int(hashlib.sha256(identity.encode("utf-8")).hexdigest()[:8], 16)
                stressed = apply_stress_condition(
                    target,
                    noise,
                    condition,
                    rng=np.random.default_rng(rng_seed),
                )
                write_pcm16_mono(destination, stressed)
            updated = dict(row)
            updated["audio_path"] = str(destination.resolve())
            updated["split_group"] = f"stress:{row['split_group']}"
            updated["stress_condition"] = condition
            updated["base_source_recording_id"] = source_id
            updated["noise_source_recording_id"] = noise_id
            output_rows.append(updated)
    for row in backgrounds:
        updated = dict(row)
        updated["audio_path"] = str(
            resolve_audio(background_source, row["audio_path"])
        )
        updated["split_group"] = f"stress:{row['split_group']}"
        updated["stress_condition"] = "background_clean"
        updated["base_source_recording_id"] = row.get("source_recording_id", "")
        updated["noise_source_recording_id"] = ""
        output_rows.append(updated)
    output_fields = fields + [
        name
        for name in ("stress_condition", "base_source_recording_id", "noise_source_recording_id")
        if name not in fields
    ]
    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    with output_manifest.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=output_fields)
        writer.writeheader()
        writer.writerows(output_rows)
    return output_rows


def main() -> None:
    parser = argparse.ArgumentParser(description="构建非鸟声音噪声与设备压力测试集")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/nonbird/stress_manifest.csv"))
    parser.add_argument("--audio-dir", type=Path, default=Path("data/interim/nonbird_stress"))
    parser.add_argument("--split", default="test")
    parser.add_argument("--conditions", default=",".join(DEFAULT_CONDITIONS))
    parser.add_argument("--max-recordings", type=int)
    parser.add_argument(
        "--background-manifest",
        type=Path,
        help="可选的独立背景声清单；官方标准声压力测试应使用此参数",
    )
    parser.add_argument("--seed", type=int, default=20260803)
    args = parser.parse_args()
    conditions = tuple(item.strip() for item in args.conditions.split(",") if item.strip())
    rows = build_stress_rows(
        args.manifest,
        output_manifest=args.output,
        audio_dir=args.audio_dir,
        split=args.split,
        conditions=conditions,
        max_recordings=args.max_recordings,
        seed=args.seed,
        background_manifest=args.background_manifest,
    )
    print(f"built {len(rows)} stress recordings at {args.output}")


if __name__ == "__main__":
    main()
