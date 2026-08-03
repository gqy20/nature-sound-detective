from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import (
    download_file,
    license_is_usable,
    normalize_license,
    write_candidates,
)


def ensure_annotation(path: Path, url: str) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "nature-sound-detective-research/0.1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        path.write_bytes(response.read())


def select_rows(
    annotation: Path,
    *,
    group: str | None,
    species: set[str],
    limit_per_species: int,
    commercial_only: bool,
) -> list[dict[str, object]]:
    counts: dict[str, int] = {}
    selected: list[dict[str, object]] = []
    with annotation.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            scientific_name = str(row["species_name"]).replace("_", " ")
            if group and row["group"].casefold() != group.casefold():
                continue
            if species and scientific_name not in species:
                continue
            if counts.get(scientific_name, 0) >= limit_per_species:
                continue
            license_info = normalize_license(row.get("license"))
            code = str(license_info["license_code"])
            if not license_is_usable(code):
                continue
            if commercial_only and not license_info["commercial_compatible"]:
                continue
            counts[scientific_name] = counts.get(scientific_name, 0) + 1
            source_id = Path(row["file_name"]).stem
            selected.append(
                {
                    "source": "insectset459",
                    "source_id": source_id,
                    "taxon_id": "other_insect",
                    "scientific_name": scientific_name,
                    "name_zh": "其他鸣虫",
                    "category_id": "insect",
                    "source_url": row.get("observation", ""),
                    "media_url": row.get("file", ""),
                    **license_info,
                    "attribution": row.get("contributor", ""),
                    "quality_grade": "research_grade" if "inaturalist.org" in row.get("observation", "") else "source_curated",
                    "split_hint": row.get("subset", "").lower(),
                    "split_group": row.get("observation", "") or source_id,
                    "review_status": "pending",
                    "review_notes": f"InsectSet459 group={row.get('group', '')}; source split preserved",
                }
            )
    return selected


def main() -> None:
    parser = argparse.ArgumentParser(description="从 InsectSet459 元数据筛选鸣虫候选")
    parser.add_argument("--config", type=Path, default=Path("ml/configs/nonbird_data_sources.json"))
    parser.add_argument("--annotation", type=Path, default=Path("data/external/insectset459/annotations.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/insectset459_candidates.csv"))
    parser.add_argument("--audio-dir", type=Path, default=Path("data/raw/insectset459"))
    parser.add_argument("--group")
    parser.add_argument("--species", action="append", default=[])
    parser.add_argument("--limit-per-species", type=int, default=20)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--commercial-only", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    source = config["insectset459"]
    group = args.group or source["default_group"]
    ensure_annotation(args.annotation, source["annotation_url"])
    rows = select_rows(
        args.annotation,
        group=group,
        species=set(args.species),
        limit_per_species=args.limit_per_species,
        commercial_only=args.commercial_only,
    )
    if args.download:
        for index, row in enumerate(rows, start=1):
            suffix = Path(urllib.parse.urlparse(str(row["media_url"])).path).suffix or ".audio"
            destination = args.audio_dir / f"{row['source_id']}{suffix}"
            row["sha256"] = download_file(str(row["media_url"]), destination)
            row["local_path"] = str(destination)
            print(f"downloaded {index}/{len(rows)} {row['source_id']}")
    written = write_candidates(rows, args.output)
    print(f"wrote {len(written)} candidates from {len({row['scientific_name'] for row in rows})} species")
    print("These broad insect records are other_insect candidates, not black-cicada positives.")


if __name__ == "__main__":
    main()
