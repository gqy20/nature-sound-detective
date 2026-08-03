from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import wave


def destination_name(row: dict[str, str]) -> str:
    identity = f"{row.get('source_dataset', '')}:{row.get('source_recording_id', '')}"
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()[:12]
    safe_id = "".join(
        character if character.isalnum() or character in {"-", "_"} else "_"
        for character in row.get("source_recording_id", "recording")
    )
    return f"{safe_id}_{digest}.wav"


def prepare(
    manifest: Path,
    *,
    output_manifest: Path,
    audio_dir: Path,
    max_seconds: float,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required")
    with manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fields = list(reader.fieldnames or [])
        source_rows = list(reader)
    prepared: list[dict[str, str]] = []
    failures: list[dict[str, str]] = []
    audio_dir.mkdir(parents=True, exist_ok=True)
    for index, row in enumerate(source_rows, start=1):
        source = Path(row["audio_path"])
        if not source.is_absolute():
            source = (manifest.parent / source).resolve()
        destination = audio_dir / destination_name(row)
        if not destination.exists():
            completed = subprocess.run(
                [
                    ffmpeg,
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-i",
                    str(source),
                    "-t",
                    str(max_seconds),
                    "-ac",
                    "1",
                    "-ar",
                    "48000",
                    "-c:a",
                    "pcm_s16le",
                    str(destination),
                ],
                capture_output=True,
                text=True,
                timeout=90,
            )
            if completed.returncode != 0:
                failures.append(
                    {
                        "source_recording_id": row.get("source_recording_id", ""),
                        "audio_path": str(source),
                        "error": completed.stderr.strip()[-500:],
                    }
                )
                print(f"warning: decode failed {index}/{len(source_rows)} {source.name}")
                continue
        try:
            with wave.open(str(destination), "rb") as audio:
                valid = (
                    audio.getframerate() == 48000
                    and audio.getnchannels() == 1
                    and audio.getsampwidth() == 2
                    and audio.getnframes() > 0
                )
        except (wave.Error, EOFError):
            valid = False
        if not valid:
            failures.append(
                {
                    "source_recording_id": row.get("source_recording_id", ""),
                    "audio_path": str(source),
                    "error": "prepared WAV contract validation failed",
                }
            )
            continue
        updated = dict(row)
        updated["audio_path"] = os.path.relpath(destination.resolve(), output_manifest.parent.resolve())
        updated["start_seconds"] = ""
        updated["end_seconds"] = ""
        prepared.append(updated)
        if index % 25 == 0:
            print(f"prepared {index}/{len(source_rows)}")
    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    with output_manifest.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(prepared)
    return prepared, failures


def main() -> None:
    parser = argparse.ArgumentParser(description="将非鸟训练音频统一为 BirdNET 48 kHz WAV")
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--output-manifest",
        type=Path,
        default=Path("data/metadata/nonbird_source_curated_prepared_manifest.csv"),
    )
    parser.add_argument(
        "--audio-dir",
        type=Path,
        default=Path("data/interim/nonbird_source_curated_48k"),
    )
    parser.add_argument("--max-seconds", type=float, default=30.0)
    args = parser.parse_args()
    rows, failures = prepare(
        args.manifest,
        output_manifest=args.output_manifest,
        audio_dir=args.audio_dir,
        max_seconds=args.max_seconds,
    )
    counts = Counter((row["labels"], row["split"]) for row in rows)
    print(f"prepared {len(rows)} rows; failures={len(failures)}")
    print(dict(sorted(counts.items())))
    if failures:
        failure_path = args.output_manifest.with_suffix(".failures.json")
        import json

        failure_path.write_text(json.dumps(failures, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
