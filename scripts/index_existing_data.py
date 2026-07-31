"""Create a non-destructive inventory of audio files currently in data/."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import soundfile as sf


AUDIO_SUFFIXES = {".wav", ".mp3", ".flac", ".ogg", ".aif", ".aiff"}
MIXTURE_MARKERS = ("背景", "至少包含", "二重奏", "&", "可能有")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def weak_label(filename: str) -> tuple[str, str]:
    xc_match = re.match(r"^XC\d+\s*-\s*(.*?)\s*-\s*", filename, re.IGNORECASE)
    if xc_match:
        return xc_match.group(1).strip(), "filename_xeno_canto"
    parts = filename.split("——")
    if len(parts) >= 2:
        label = parts[1].split("——", 1)[0].strip()
        return label, "filename_local"
    return "", "unknown"


def audio_info(path: Path) -> dict[str, object]:
    try:
        info = sf.info(path)
        return {
            "duration_seconds": round(float(info.duration), 6),
            "samplerate": int(info.samplerate),
            "channels": int(info.channels),
            "frames": int(info.frames),
            "audio_format": info.format,
            "audio_subtype": info.subtype,
            "read_error": "",
        }
    except Exception as exc:  # keep indexing even when one codec is unsupported
        return {
            "duration_seconds": "",
            "samplerate": "",
            "channels": "",
            "frames": "",
            "audio_format": "",
            "audio_subtype": "",
            "read_error": f"{type(exc).__name__}: {exc}",
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/metadata"))
    args = parser.parse_args()

    data_dir = args.data_dir.resolve()
    paths = sorted(
        path for path in data_dir.iterdir()
        if path.is_file() and path.suffix.lower() in AUDIO_SUFFIXES
    )
    generated_at = datetime.now(timezone.utc).isoformat()
    rows: list[dict[str, object]] = []

    for path in paths:
        label, label_basis = weak_label(path.name)
        source_id_match = re.match(r"^(XC\d+)", path.name, re.IGNORECASE)
        source = "xeno_canto" if source_id_match else "local_or_shared"
        row: dict[str, object] = {
            "recording_id": path.stem,
            "source": source,
            "source_id": source_id_match.group(1).upper() if source_id_match else "",
            "filename": path.name,
            "current_path": str(path),
            "bytes": path.stat().st_size,
            "suffix": path.suffix.lower(),
            "sha256": sha256_file(path),
            "primary_label_weak": label,
            "label_basis": label_basis,
            "mixture_hint": any(marker in path.name for marker in MIXTURE_MARKERS),
            "review_status": "pending",
            "license": "",
            "source_url": "",
            "reviewed_primary_label": "",
            "background_labels": "",
            "valid_intervals": "",
            "review_notes": "",
            "indexed_at": generated_at,
        }
        row.update(audio_info(path))
        rows.append(row)

    hashes: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        hashes[str(row["sha256"])].append(row)
    duplicate_groups = [group for group in hashes.values() if len(group) > 1]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_dir / "existing_recordings.csv"
    if rows:
        with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)

    duplicate_path = args.output_dir / "duplicate_groups.json"
    duplicate_path.write_text(
        json.dumps(
            [
                {
                    "sha256": group[0]["sha256"],
                    "bytes": group[0]["bytes"],
                    "files": [row["current_path"] for row in group],
                }
                for group in duplicate_groups
            ],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"Indexed audio files: {len(rows)}")
    print(f"Duplicate groups: {len(duplicate_groups)}")
    print(f"Inventory: {csv_path.resolve()}")
    print(f"Duplicates: {duplicate_path.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

