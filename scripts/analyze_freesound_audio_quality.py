"""Add objective level, silence and clipping features to the review queue."""

from __future__ import annotations

import argparse
import csv
import math
import os
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf


def dbfs(value: float) -> float:
    return 20 * math.log10(max(value, 1e-12))


def analyze(path: Path) -> dict[str, Any]:
    total_squares = 0.0
    total_samples = 0
    peak = 0.0
    clipping_samples = 0
    silent_blocks = 0
    block_count = 0
    try:
        with sf.SoundFile(path) as audio:
            block_size = max(int(audio.samplerate * 0.1), 1)
            for block in audio.blocks(blocksize=block_size, always_2d=True, dtype="float32"):
                absolute = np.abs(block)
                peak = max(peak, float(absolute.max(initial=0.0)))
                total_squares += float(np.square(block, dtype=np.float64).sum())
                total_samples += int(block.size)
                clipping_samples += int((absolute >= 0.999).sum())
                block_rms = math.sqrt(float(np.square(block, dtype=np.float64).mean())) if block.size else 0.0
                silent_blocks += int(dbfs(block_rms) < -50)
                block_count += 1
        rms = math.sqrt(total_squares / total_samples) if total_samples else 0.0
        silent_fraction = silent_blocks / block_count if block_count else 1.0
        clipping_fraction = clipping_samples / total_samples if total_samples else 0.0
        if rms <= 1e-10:
            quality = "silent_reject_candidate"
        elif rms < 10 ** (-45 / 20):
            quality = "very_quiet_review"
        elif silent_fraction > 0.8:
            quality = "sparse_or_silent_review"
        elif clipping_fraction > 0.001:
            quality = "clipping_review"
        else:
            quality = "usable_level_candidate"
        return {
            "quality_flag": quality,
            "rms_dbfs": round(dbfs(rms), 3),
            "peak_dbfs": round(dbfs(peak), 3),
            "silent_block_fraction": round(silent_fraction, 6),
            "clipping_sample_fraction": round(clipping_fraction, 8),
            "quality_read_error": "",
        }
    except Exception as exc:
        return {
            "quality_flag": "unreadable_reject_candidate",
            "rms_dbfs": "",
            "peak_dbfs": "",
            "silent_block_fraction": "",
            "clipping_sample_fraction": "",
            "quality_read_error": f"{type(exc).__name__}: {exc}",
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--queue", type=Path, default=Path("data/metadata/freesound_review_queue.csv"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or args.queue

    with args.queue.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    for index, row in enumerate(rows, start=1):
        row.update(analyze(Path(row["local_path"])))
        item_id = row.get("item_id") or row.get("freesound_id") or row.get("recording_id", "unknown")
        safe_item_id = str(item_id).encode("ascii", "backslashreplace").decode("ascii")
        print(f"quality {index}/{len(rows)} id={safe_item_id} {row['quality_flag']}", flush=True)

    fields = sorted({key for row in rows for key in row})
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, output)
    print(f"Updated review queue: {output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
