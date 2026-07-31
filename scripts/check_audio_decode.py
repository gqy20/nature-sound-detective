"""Decode every stage-1 preview in an isolated process and report codec warnings."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path


def decode_one(path: Path) -> int:
    import soundfile as sf

    frames = 0
    with sf.SoundFile(path) as audio:
        for block in audio.blocks(blocksize=max(audio.samplerate, 1), dtype="float32"):
            frames += len(block)
        payload = {
            "frames": frames,
            "samplerate": audio.samplerate,
            "channels": audio.channels,
            "duration_seconds": frames / audio.samplerate,
        }
    print(json.dumps(payload))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("data/metadata/freesound_candidates.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/freesound_decode_check.csv"))
    parser.add_argument("--one", type=Path)
    args = parser.parse_args()

    if args.one:
        return decode_one(args.one)

    with args.manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        source_rows = list(csv.DictReader(handle))

    results: list[dict[str, str]] = []
    for index, row in enumerate(source_rows, start=1):
        path = Path(row["local_path"])
        item_id = row.get("item_id") or row.get("freesound_id") or row.get("recording_id", "unknown")
        process = subprocess.run(
            [sys.executable, __file__, "--one", str(path)],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
        decoded: dict[str, object] = {}
        if process.returncode == 0:
            try:
                decoded = json.loads(process.stdout.strip().splitlines()[-1])
            except (IndexError, json.JSONDecodeError):
                pass
        expected_duration = float(row.get("duration_seconds") or 0)
        actual_duration = float(decoded.get("duration_seconds") or 0)
        duration_delta = actual_duration - expected_duration
        stderr = process.stderr.strip()
        status = "ok"
        if process.returncode != 0 or not decoded:
            status = "decode_failed"
        elif stderr:
            status = "decoded_with_codec_warning"
        elif abs(duration_delta) > 0.25:
            status = "duration_mismatch_review"
        results.append(
            {
                "item_id": item_id,
                "dataset_key": row.get("dataset_key", "freesound"),
                "freesound_id": row.get("freesound_id", ""),
                "recording_id": row.get("recording_id", ""),
                "local_path": row["local_path"],
                "decode_status": status,
                "return_code": str(process.returncode),
                "codec_stderr": stderr.replace("\r", " ").replace("\n", " | "),
                "expected_duration_seconds": f"{expected_duration:.6f}",
                "decoded_duration_seconds": f"{actual_duration:.6f}",
                "duration_delta_seconds": f"{duration_delta:.6f}",
                "samplerate": str(decoded.get("samplerate", "")),
                "channels": str(decoded.get("channels", "")),
            }
        )
        safe_item_id = str(item_id).encode("ascii", "backslashreplace").decode("ascii")
        print(f"decode {index}/{len(source_rows)} id={safe_item_id} {status}", flush=True)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)

    status_counts: dict[str, int] = {}
    for row in results:
        status_counts[row["decode_status"]] = status_counts.get(row["decode_status"], 0) + 1
    print(json.dumps(status_counts, ensure_ascii=False, sort_keys=True))
    print(f"decode_report={args.output.resolve()}")
    return int(any(row["decode_status"] == "decode_failed" for row in results))


if __name__ == "__main__":
    raise SystemExit(main())
