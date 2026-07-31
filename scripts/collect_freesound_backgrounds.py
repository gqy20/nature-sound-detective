"""Collect Freesound background candidates with licenses and review metadata."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


FIELDS = [
    "id", "name", "url", "username", "license", "tags", "description",
    "duration", "samplerate", "channels", "type", "filesize", "md5",
    "created", "geotag", "previews", "avg_rating", "num_ratings", "num_downloads",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def normalize_license(value: str) -> dict[str, object]:
    lower = value.lower()
    if "zero" in lower or "/publicdomain/" in lower or "/cc0/" in lower:
        return {"license_code": "CC0", "commercial_compatible": True, "attribution_required": False}
    if "noncommercial" in lower or "by-nc" in lower:
        return {"license_code": "CC-BY-NC", "commercial_compatible": False, "attribution_required": True}
    if "attribution" in lower or "/by/" in lower:
        return {"license_code": "CC-BY", "commercial_compatible": True, "attribution_required": True}
    return {"license_code": "UNKNOWN", "commercial_compatible": False, "attribution_required": True}


def api_get(url: str, token: str, params: dict[str, object], retries: int = 3) -> dict[str, Any]:
    request_url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        request_url,
        headers={"Authorization": f"Token {token}", "User-Agent": "nature-sound-detective/0.1"},
    )
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code == 429 or 500 <= exc.code < 600:
                if attempt + 1 < retries:
                    time.sleep(2 ** attempt)
                    continue
            detail = exc.read(500).decode("utf-8", errors="replace")
            raise RuntimeError(f"Freesound API HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            if attempt + 1 < retries:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f"Freesound API connection failed: {exc.reason}") from exc
    raise RuntimeError("Freesound API request failed")


def select_preview(previews: dict[str, str]) -> tuple[str, str]:
    for key, extension in (("preview-hq-ogg", ".ogg"), ("preview-hq-mp3", ".mp3")):
        if previews.get(key):
            return previews[key], extension
    return "", ""


def download_preview(url: str, destination: Path) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "nature-sound-detective/0.1"})
    with urllib.request.urlopen(request, timeout=90) as response, partial.open("wb") as handle:
        while chunk := response.read(1024 * 1024):
            handle.write(chunk)
            digest.update(chunk)
    os.replace(partial, destination)
    return digest.hexdigest()


def load_existing(path: Path) -> dict[int, dict[str, Any]]:
    if not path.exists():
        return {}
    records: dict[int, dict[str, Any]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            record = json.loads(line)
            records[int(record["freesound_id"])] = record
    return records


def write_manifests(records: list[dict[str, Any]], jsonl_path: Path, csv_path: Path) -> None:
    jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    jsonl_path.write_text(
        "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
        encoding="utf-8",
    )
    if not records:
        return
    csv_fields = [key for key in records[0] if key not in {"tags", "previews"}]
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=csv_fields, extrasaction="ignore")
        writer.writeheader()
        for record in records:
            row = dict(record)
            row["tags"] = "|".join(record.get("tags", []))
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path("ml/configs/freesound_background_queries.json"))
    parser.add_argument("--metadata-dir", type=Path, default=Path("data/metadata"))
    parser.add_argument("--preview-dir", type=Path, default=Path("data/raw/freesound/previews"))
    parser.add_argument("--response-dir", type=Path, default=Path("data/raw/freesound/api_responses"))
    parser.add_argument("--target-per-category", type=int)
    parser.add_argument("--download-previews", action="store_true")
    parser.add_argument("--commercial-only", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("FREESOUND_API_TOKEN", "").strip()
    if not token:
        raise SystemExit("FREESOUND_API_TOKEN is not configured. See .env.example and docs/07-data-stage-1.md")

    config = json.loads(args.config.read_text(encoding="utf-8"))
    target = args.target_per_category or int(config["target_per_category"])
    duration = config["duration_seconds"]
    jsonl_path = args.metadata_dir / "freesound_candidates.jsonl"
    csv_path = args.metadata_dir / "freesound_candidates.csv"
    existing = load_existing(jsonl_path)
    selected_ids = set(existing)
    collected = dict(existing)
    run_stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    for category in config["categories"]:
        params = {
            "query": category["query"],
            "filter": f"duration:[{duration['min']} TO {duration['max']}]",
            "fields": ",".join(FIELDS),
            "page_size": min(max(target * 5, 50), 150),
            "sort": "rating_desc",
        }
        payload = api_get(config["api_url"], token, params)
        args.response_dir.mkdir(parents=True, exist_ok=True)
        response_path = args.response_dir / f"{run_stamp}_{category['slug']}.json"
        response_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

        accepted_for_category = 0
        for sound in payload.get("results", []):
            sound_id = int(sound["id"])
            if sound_id in selected_ids:
                continue
            license_info = normalize_license(str(sound.get("license", "")))
            if args.commercial_only and not license_info["commercial_compatible"]:
                continue
            preview_url, extension = select_preview(sound.get("previews") or {})
            if not preview_url:
                continue

            local_path = args.preview_dir / category["slug"] / f"freesound_{sound_id}{extension}"
            preview_sha256 = ""
            downloaded_at = ""
            if args.download_previews:
                if not local_path.exists():
                    preview_sha256 = download_preview(preview_url, local_path)
                    time.sleep(0.1)
                else:
                    preview_sha256 = hashlib.sha256(local_path.read_bytes()).hexdigest()
                downloaded_at = utc_now()

            record = {
                "source": "freesound",
                "freesound_id": sound_id,
                "category": category["slug"],
                "category_name_zh": category["name_zh"],
                "intended_use": category["intended_use"],
                "query": category["query"],
                "name": sound.get("name", ""),
                "username": sound.get("username", ""),
                "sound_url": sound.get("url", f"https://freesound.org/s/{sound_id}/"),
                "license": sound.get("license", ""),
                **license_info,
                "attribution_text": f"{sound.get('name', '')} by {sound.get('username', '')} ({license_info['license_code']})",
                "tags": sound.get("tags", []),
                "description": sound.get("description", ""),
                "duration_seconds": sound.get("duration", ""),
                "samplerate": sound.get("samplerate", ""),
                "channels": sound.get("channels", ""),
                "original_type": sound.get("type", ""),
                "original_filesize": sound.get("filesize", ""),
                "original_md5": sound.get("md5", ""),
                "created": sound.get("created", ""),
                "geotag": sound.get("geotag", ""),
                "avg_rating": sound.get("avg_rating", ""),
                "num_ratings": sound.get("num_ratings", ""),
                "num_downloads": sound.get("num_downloads", ""),
                "preview_kind": "hq-ogg" if extension == ".ogg" else "hq-mp3",
                "preview_url": preview_url,
                "local_path": str(local_path) if args.download_previews else "",
                "preview_sha256": preview_sha256,
                "downloaded_at": downloaded_at,
                "review_status": "pending",
                "reviewed_class": "",
                "contains_target_species": "",
                "contains_speech": "",
                "privacy_risk": "",
                "valid_intervals": "",
                "review_notes": "",
                "collected_at": utc_now(),
            }
            collected[sound_id] = record
            selected_ids.add(sound_id)
            accepted_for_category += 1
            if accepted_for_category >= target:
                break
        print(f"{category['slug']}: added {accepted_for_category}/{target}")
        time.sleep(1.1)

    records = sorted(collected.values(), key=lambda item: (item["category"], int(item["freesound_id"])))
    write_manifests(records, jsonl_path, csv_path)
    print(f"Candidates total: {len(records)}")
    print(f"Manifest: {csv_path.resolve()}")
    print("All new candidates remain review_status=pending.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

