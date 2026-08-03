from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import time
from typing import Any
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import (
    download_file,
    license_is_usable,
    mark_duplicate_audio,
    normalize_license,
    write_candidates,
)


def api_get(url: str, params: dict[str, object]) -> dict[str, Any]:
    request_url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        request_url,
        headers={"User-Agent": "nature-sound-detective-research/0.1"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def sound_extension(sound: dict[str, Any]) -> str:
    media_type = str(sound.get("file_content_type", "")).lower()
    if media_type == "audio/mpeg":
        return ".mp3"
    if media_type in {"audio/mp4", "audio/x-m4a"}:
        return ".m4a"
    suffix = Path(urllib.parse.urlparse(str(sound.get("file_url", ""))).path).suffix
    return suffix if suffix else ".audio"


def observation_records(
    observation: dict[str, Any],
    taxon: dict[str, Any],
    *,
    commercial_only: bool,
    trust_source_labels: bool = False,
) -> list[dict[str, Any]]:
    coordinates = (observation.get("geojson") or {}).get("coordinates") or ["", ""]
    rows: list[dict[str, Any]] = []
    for sound in observation.get("sounds") or []:
        license_info = normalize_license(sound.get("license_code"))
        code = str(license_info["license_code"])
        if not license_is_usable(code):
            continue
        if commercial_only and not license_info["commercial_compatible"]:
            continue
        sound_id = str(sound["id"])
        observation_id = str(observation["id"])
        taxon_fields = dict(taxon)
        if taxon.get("preserve_observed_taxon"):
            taxon_fields["scientific_name"] = (observation.get("taxon") or {}).get("name", "")
        rows.append(
            {
                "source": "inaturalist",
                "source_id": f"inat_{observation_id}_{sound_id}",
                **taxon_fields,
                "source_url": observation.get("uri", f"https://www.inaturalist.org/observations/{observation_id}"),
                "media_url": sound.get("file_url", ""),
                **license_info,
                "attribution": sound.get("attribution", ""),
                "quality_grade": observation.get("quality_grade", ""),
                "observed_on": observation.get("observed_on", ""),
                "longitude": coordinates[0] if len(coordinates) > 1 else "",
                "latitude": coordinates[1] if len(coordinates) > 1 else "",
                "locality": observation.get("place_guess", ""),
                "split_group": f"inaturalist_observation_{observation_id}",
                "review_status": "source_curated" if trust_source_labels else "pending",
                "review_notes": (
                    "trusted iNaturalist research-grade community label"
                    if trust_source_labels
                    else ""
                ),
            }
        )
    return rows


def collect(
    config: dict[str, Any],
    *,
    limit_per_taxon: int | None,
    commercial_only: bool,
    trust_source_labels: bool = False,
) -> list[dict[str, Any]]:
    source = config["inaturalist"]
    all_rows: list[dict[str, Any]] = []
    for taxon in source["taxa"]:
        target = limit_per_taxon or int(taxon["target_count"])
        page = 1
        taxon_rows: list[dict[str, Any]] = []
        while len(taxon_rows) < target:
            payload = api_get(
                source["api_url"],
                {
                    "taxon_name": taxon.get("query_name") or taxon["scientific_name"],
                    "sounds": "true",
                    "quality_grade": source["quality_grade"],
                    "place_id": source["place_id"],
                    "per_page": 200,
                    "page": page,
                    "order_by": "observed_on",
                    "order": "desc",
                },
            )
            observations = payload.get("results") or []
            if not observations:
                break
            for observation in observations:
                observed_taxon = str((observation.get("taxon") or {}).get("name", ""))
                if observed_taxon in set(taxon.get("exclude_scientific_names", [])):
                    continue
                taxon_rows.extend(
                    observation_records(
                        observation,
                        taxon,
                        commercial_only=commercial_only,
                        trust_source_labels=trust_source_labels,
                    )
                )
                if len(taxon_rows) >= target:
                    break
            if page * 200 >= int(payload.get("total_results", 0)):
                break
            page += 1
            time.sleep(0.5)
        query_name = taxon.get("query_name") or taxon["scientific_name"]
        print(f"{query_name}: {len(taxon_rows[:target])} candidates")
        all_rows.extend(taxon_rows[:target])
    return all_rows


def main() -> None:
    parser = argparse.ArgumentParser(description="收集 iNaturalist 中国蛙类与鸣虫声音候选")
    parser.add_argument("--config", type=Path, default=Path("ml/configs/nonbird_data_sources.json"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/inaturalist_nonbird_candidates.csv"))
    parser.add_argument("--audio-dir", type=Path, default=Path("data/raw/inaturalist"))
    parser.add_argument("--limit-per-taxon", type=int)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--commercial-only", action="store_true")
    parser.add_argument("--trust-source-labels", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    rows = collect(
        config,
        limit_per_taxon=args.limit_per_taxon,
        commercial_only=args.commercial_only,
        trust_source_labels=args.trust_source_labels,
    )
    if args.download:
        for index, row in enumerate(rows, start=1):
            destination = args.audio_dir / row["taxon_id"] / (
                row["source_id"] + sound_extension({
                    "file_url": row["media_url"],
                    "file_content_type": "",
                })
            )
            try:
                row["sha256"] = (
                    download_file(row["media_url"], destination)
                    if not destination.exists()
                    else hashlib.sha256(destination.read_bytes()).hexdigest()
                )
                row["local_path"] = str(destination)
                print(f"downloaded {index}/{len(rows)} {row['source_id']}")
            except Exception as exc:
                row["review_notes"] = f"download_failed:{type(exc).__name__}"
                print(f"warning: failed {index}/{len(rows)} {row['source_id']}: {type(exc).__name__}")
            write_candidates(rows, args.output)
            time.sleep(0.15)
        duplicates = mark_duplicate_audio(rows)
        if duplicates:
            print(f"marked {duplicates} duplicate audio records")
    written = write_candidates(rows, args.output)
    print(f"wrote {len(written)} candidates to {args.output}")
    print("All records remain review_status=pending until a human listens to them.")


if __name__ == "__main__":
    main()
