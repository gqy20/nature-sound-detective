from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path
import sys
import urllib.parse

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import (
    download_file,
    license_is_usable,
    normalize_license,
    write_candidates,
)


REQUIRED_FIELDS = {
    "source",
    "source_id",
    "taxon_id",
    "name_zh",
    "category_id",
    "source_url",
    "media_url",
    "license",
    "attribution",
    "review_status",
}


def load_curated_rows(path: Path, *, commercial_only: bool) -> tuple[list[dict[str, object]], list[str]]:
    accepted: list[dict[str, object]] = []
    warnings: list[str] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_FIELDS - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"人工来源清单缺少字段: {sorted(missing)}")
        for line_number, row in enumerate(reader, start=2):
            license_info = normalize_license(row.get("license"))
            code = str(license_info["license_code"])
            media_url = (row.get("media_url") or "").strip()
            if not media_url:
                warnings.append(f"line {line_number}: missing media_url ({row.get('source_id', '')})")
                continue
            if not license_is_usable(code):
                warnings.append(f"line {line_number}: unusable license {code} ({row.get('source_id', '')})")
                continue
            if commercial_only and not license_info["commercial_compatible"]:
                continue
            accepted.append(
                {
                    **row,
                    **license_info,
                    "split_group": row.get("split_group") or f"{row['source']}_{row['source_id']}",
                    "review_status": row.get("review_status") or "pending",
                }
            )
    return accepted, warnings


def main() -> None:
    parser = argparse.ArgumentParser(description="导入人工整理的国内蛙虫声音来源")
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/metadata/curated_nonbird_candidates.csv"))
    parser.add_argument("--audio-dir", type=Path, default=Path("data/raw/curated_nonbird"))
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--commercial-only", action="store_true")
    args = parser.parse_args()
    rows, warnings = load_curated_rows(args.input, commercial_only=args.commercial_only)
    for warning in warnings:
        print(f"warning: {warning}")
    if args.download:
        for index, row in enumerate(rows, start=1):
            suffix = Path(urllib.parse.urlparse(str(row["media_url"])).path).suffix or ".audio"
            destination = args.audio_dir / str(row["taxon_id"]) / f"{row['source_id']}{suffix}"
            row["sha256"] = (
                hashlib.sha256(destination.read_bytes()).hexdigest()
                if destination.exists()
                else download_file(str(row["media_url"]), destination)
            )
            row["local_path"] = str(destination)
            print(f"downloaded {index}/{len(rows)} {row['source_id']}")
    write_candidates(rows, args.output)
    print(f"wrote {len(rows)} licensed candidates to {args.output}")


if __name__ == "__main__":
    main()
