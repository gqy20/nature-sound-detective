from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path
import shutil
import subprocess


AUDIO_EXTENSIONS = {".wav", ".m4a", ".mp3"}
FIELDS = ("category", "species_name_zh", "source_path", "prepared_path", "source_sha256")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="将官方标准声无损统一为BirdNET 48k单声道WAV")
    parser.add_argument(
        "--source-root",
        type=Path,
        default=Path("data/raw/challenge_2026/standard_sounds"),
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("data/interim/challenge_2026_standard_48k_v2"),
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("data/metadata/challenge_2026_standard_prepared.csv"),
    )
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise SystemExit("ffmpeg is required")
    rows: list[dict[str, str]] = []
    sources = sorted(
        path
        for path in args.source_root.rglob("*")
        if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS
    )
    for index, source in enumerate(sources, start=1):
        relative = source.relative_to(args.source_root)
        destination = args.output_root / relative.parent / (
            f"{source.stem}__{source.suffix.lower().lstrip('.')}.wav"
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        completed = subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(source),
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
            timeout=180,
        )
        if completed.returncode:
            raise RuntimeError(f"标准声转码失败：{source}\n{completed.stderr[-500:]}")
        rows.append(
            {
                "category": relative.parts[0],
                "species_name_zh": relative.parts[1],
                "source_path": source.as_posix(),
                "prepared_path": destination.as_posix(),
                "source_sha256": digest(source),
            }
        )
        print(f"prepared {index}/{len(sources)} {relative}", flush=True)
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    with args.manifest.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"prepared {len(rows)} official files; manifest={args.manifest}")


if __name__ == "__main__":
    main()
