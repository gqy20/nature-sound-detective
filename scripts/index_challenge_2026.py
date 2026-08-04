from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import wave


AUDIO_EXTENSIONS = {".wav", ".m4a", ".mp3"}
PERIOD_PATTERN = re.compile(r"^2026[A-D]\b")
CAPTURE_PATTERN = re.compile(r"_(\d{8})_(\d{6})\.wav$", re.IGNORECASE)
FIELDS = (
    "recording_id",
    "dataset_kind",
    "period",
    "category_id",
    "species_name_zh",
    "relative_path",
    "captured_at",
    "byte_length",
    "duration_seconds",
    "sample_rate",
    "channels",
    "bit_depth",
    "sha256",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def wav_metadata(path: Path) -> tuple[float, int, int, int]:
    with wave.open(str(path), "rb") as audio:
        return (
            audio.getnframes() / audio.getframerate(),
            audio.getframerate(),
            audio.getnchannels(),
            audio.getsampwidth() * 8,
        )


def compressed_duration(path: Path) -> float:
    completed = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return float(completed.stdout.strip())


def load_catalog(path: Path) -> tuple[dict[str, dict[str, object]], dict[str, str]]:
    value = json.loads(path.read_text(encoding="utf-8"))
    by_name: dict[str, dict[str, object]] = {}
    aliases: dict[str, str] = {}
    for row in value["classes"]:
        name = str(row["name_zh"])
        by_name[name] = row
        aliases[name] = name
        for alias in row.get("aliases", []):
            aliases[str(alias)] = name
    return by_name, aliases


def index(root: Path, catalog_path: Path, *, with_hashes: bool) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    catalog, aliases = load_catalog(catalog_path)
    rows: list[dict[str, object]] = []
    issues: list[dict[str, object]] = []
    standard_root = root / "杭州常见物种标准声音"
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if path.name.endswith(".crdownload"):
            issues.append({"code": "partial_download", "relative_path": str(relative), "byte_length": path.stat().st_size})
            continue
        if path.suffix.lower() not in AUDIO_EXTENSIONS:
            continue
        dataset_kind = "standard" if standard_root in path.parents else "wild"
        period = relative.parts[0] if dataset_kind == "wild" else ""
        if dataset_kind == "wild" and not PERIOD_PATTERN.match(period):
            continue
        category_id = ""
        species_name = ""
        captured_at = ""
        if dataset_kind == "standard":
            raw_species = path.parent.name
            species_name = aliases.get(raw_species, raw_species)
            category_name = path.parent.parent.name
            category_id = {"鸟": "bird", "虫": "insect", "蛙": "frog"}.get(category_name, "")
            if species_name not in catalog:
                issues.append({"code": "unknown_standard_species", "relative_path": str(relative), "species_name": raw_species})
        else:
            matched = CAPTURE_PATTERN.search(path.name)
            if matched:
                captured_at = datetime.strptime("".join(matched.groups()), "%Y%m%d%H%M%S").isoformat()
            else:
                issues.append({"code": "unparsed_capture_time", "relative_path": str(relative)})
        try:
            if path.suffix.lower() == ".wav":
                duration, sample_rate, channels, bit_depth = wav_metadata(path)
            else:
                duration = compressed_duration(path)
                sample_rate = channels = bit_depth = 0
        except Exception as error:
            issues.append({"code": "audio_metadata_failed", "relative_path": str(relative), "error": type(error).__name__})
            continue
        identity = hashlib.sha256(str(relative).encode("utf-8")).hexdigest()[:20]
        rows.append(
            {
                "recording_id": f"challenge_{identity}",
                "dataset_kind": dataset_kind,
                "period": period,
                "category_id": category_id,
                "species_name_zh": species_name,
                "relative_path": relative.as_posix(),
                "captured_at": captured_at,
                "byte_length": path.stat().st_size,
                "duration_seconds": round(duration, 3),
                "sample_rate": sample_rate,
                "channels": channels,
                "bit_depth": bit_depth,
                "sha256": sha256_file(path) if with_hashes else "",
            }
        )
    return rows, issues


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="索引生声不息挑战数据，不复制野外录音")
    parser.add_argument("source_root", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path("ml/configs/challenge_2026_species.json"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/challenge_2026_audio_index.csv"))
    parser.add_argument("--issues", type=Path, default=Path("data/metadata/challenge_2026_data_issues.json"))
    parser.add_argument("--sha256", action="store_true")
    args = parser.parse_args()
    root = args.source_root.resolve()
    if not root.is_dir():
        raise SystemExit(f"数据目录不存在：{root}")
    rows, issues = index(root, args.catalog, with_hashes=args.sha256)
    write_csv(args.output, rows)
    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_root": str(root),
        "copied_wild_audio": False,
        "indexed_recordings": len(rows),
        "standard_recordings": sum(row["dataset_kind"] == "standard" for row in rows),
        "wild_recordings": sum(row["dataset_kind"] == "wild" for row in rows),
        "indexed_bytes": sum(int(row["byte_length"]) for row in rows),
        "indexed_duration_seconds": round(sum(float(row["duration_seconds"]) for row in rows), 3),
        "issues": issues,
    }
    args.issues.parent.mkdir(parents=True, exist_ok=True)
    args.issues.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
