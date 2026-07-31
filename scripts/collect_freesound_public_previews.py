"""Collect public Freesound previews without an API token.

This fallback reads public search/detail HTML and downloads only CDN preview
files. It never attempts the login-protected original-file endpoint.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


BASE_URL = "https://freesound.org"
USER_AGENT = "nature-sound-detective-research/0.1"


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def fetch_text(url: str, retries: int = 2) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                encoding = response.headers.get_content_charset() or "utf-8"
                return response.read().decode(encoding, errors="replace")
        except Exception:
            if attempt + 1 >= retries:
                raise
            time.sleep(2 ** attempt)
    raise RuntimeError(f"Unable to fetch {url}")


def first_match(pattern: str, text: str, default: str = "") -> str:
    match = re.search(pattern, text, flags=re.IGNORECASE | re.DOTALL)
    return html.unescape(match.group(1).strip()) if match else default


def normalize_license(url: str, label: str) -> dict[str, object]:
    value = f"{url} {label}".lower()
    if "/zero/" in value or "/cc0/" in value or "creative commons 0" in value:
        return {"license_code": "CC0", "commercial_compatible": True, "attribution_required": False}
    if "/by-nc/" in value or "noncommercial" in value:
        return {"license_code": "CC-BY-NC", "commercial_compatible": False, "attribution_required": True}
    if "/by/" in value or "attribution" in value:
        return {"license_code": "CC-BY", "commercial_compatible": True, "attribution_required": True}
    return {"license_code": "UNKNOWN", "commercial_compatible": False, "attribution_required": True}


def parse_detail(sound_id: int, page: str) -> dict[str, Any] | None:
    title = first_match(r'data-title="([^"]+)"', page)
    duration_raw = first_match(r'data-duration="([^"]+)"', page)
    samplerate_raw = first_match(r'data-samplerate="([^"]+)"', page)
    downloads_raw = first_match(r'data-num-downloads="([^"]+)"', page)
    username = first_match(rf'/people/([^/]+)/sounds/{sound_id}/', page)

    preview_urls = list(dict.fromkeys(re.findall(
        r'https://cdn\.freesound\.org/previews/[^"\'\s<>]+-hq\.(?:ogg|mp3)', page, flags=re.IGNORECASE
    )))
    preview_url = next((url for url in preview_urls if url.lower().endswith(".ogg")), "")
    if not preview_url:
        preview_url = next((url for url in preview_urls if url.lower().endswith(".mp3")), "")

    license_match = re.search(
        r'<a[^>]+href="([^"]*creativecommons\.org[^"]*)"[^>]*>([^<]+)</a>',
        page,
        flags=re.IGNORECASE | re.DOTALL,
    )
    license_url = html.unescape(license_match.group(1)) if license_match else ""
    license_label = html.unescape(license_match.group(2).strip()) if license_match else ""
    license_info = normalize_license(license_url, license_label)

    if not title or not preview_url or license_info["license_code"] == "UNKNOWN":
        return None
    try:
        duration = float(duration_raw)
    except ValueError:
        return None

    tags = sorted(set(html.unescape(tag) for tag in re.findall(r'/browse/tags/([^/"?]+)/', page)))
    return {
        "freesound_id": sound_id,
        "name": title,
        "username": username,
        "duration_seconds": duration,
        "samplerate": float(samplerate_raw) if samplerate_raw else "",
        "num_downloads": int(downloads_raw) if downloads_raw.isdigit() else "",
        "tags": tags,
        "preview_url": preview_url,
        "preview_kind": "hq-ogg" if preview_url.lower().endswith(".ogg") else "hq-mp3",
        "license": license_url,
        "license_label": license_label,
        **license_info,
    }


def parse_search_candidates(page: str) -> list[dict[str, Any]]:
    """Read cheap duration/title metadata before requesting detail pages."""
    starts = list(re.finditer(r'data-sound-id="(\d+)"', page))
    candidates: list[dict[str, Any]] = []
    for index, match in enumerate(starts):
        end = starts[index + 1].start() if index + 1 < len(starts) else len(page)
        segment = page[match.start():end]
        duration_raw = first_match(r'data-duration="([^"]+)"', segment)
        try:
            duration = float(duration_raw)
        except ValueError:
            continue
        candidates.append({
            "sound_id": int(match.group(1)),
            "duration_seconds": duration,
            "title": first_match(r'data-title="([^"]+)"', segment),
        })
    return candidates


def download(url: str, destination: Path) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as handle:
        while chunk := response.read(1024 * 1024):
            handle.write(chunk)
            digest.update(chunk)
    os.replace(partial, destination)
    return digest.hexdigest()


def load_records(path: Path) -> dict[int, dict[str, Any]]:
    if not path.exists():
        return {}
    result: dict[int, dict[str, Any]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            record = json.loads(line)
            result[int(record["freesound_id"])] = record
    return result


def write_records(records: list[dict[str, Any]], jsonl_path: Path, csv_path: Path) -> None:
    jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    jsonl_path.write_text(
        "".join(json.dumps(record, ensure_ascii=False) + "\n" for record in records),
        encoding="utf-8",
    )
    fields = sorted({key for record in records for key in record if key != "tags"}) + ["tags"]
    with csv_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
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
    parser.add_argument("--target-per-category", type=int)
    parser.add_argument("--max-search-pages", type=int, default=4)
    parser.add_argument("--commercial-only", action="store_true")
    parser.add_argument("--request-delay", type=float, default=1.0)
    parser.add_argument("--category", action="append", help="Only collect the given category slug; repeatable")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    target = args.target_per_category or int(config["target_per_category"])
    min_duration = float(config["duration_seconds"]["min"])
    max_duration = float(config["duration_seconds"]["max"])
    jsonl_path = args.metadata_dir / "freesound_candidates.jsonl"
    csv_path = args.metadata_dir / "freesound_candidates.csv"
    records_by_id = load_records(jsonl_path)
    used_ids = set(records_by_id)

    categories = config["categories"]
    if args.category:
        known = {category["slug"] for category in categories}
        unknown = sorted(set(args.category) - known)
        if unknown:
            raise SystemExit(f"Unknown category: {', '.join(unknown)}")
        categories = [category for category in categories if category["slug"] in set(args.category)]

    for category in categories:
        category_count = sum(1 for row in records_by_id.values() if row.get("category") == category["slug"])
        if category_count >= target:
            print(f"{category['slug']}: already has {category_count}/{target}")
            continue

        for page_number in range(1, args.max_search_pages + 1):
            query = urllib.parse.urlencode({"q": category["query"], "page": page_number})
            search_url = f"{BASE_URL}/search/?{query}"
            search_page = fetch_text(search_url)
            search_candidates = parse_search_candidates(search_page)
            if not search_candidates:
                break

            for candidate in search_candidates:
                sound_id = int(candidate["sound_id"])
                if sound_id in used_ids:
                    continue
                if not min_duration <= float(candidate["duration_seconds"]) <= max_duration:
                    continue
                sound_url = f"{BASE_URL}/s/{sound_id}/"
                try:
                    detail = parse_detail(sound_id, fetch_text(sound_url))
                except Exception as exc:
                    print(f"{category['slug']}: skip {sound_id}, detail error: {type(exc).__name__}", flush=True)
                    time.sleep(args.request_delay)
                    continue
                time.sleep(args.request_delay)
                if not detail:
                    continue
                if not min_duration <= float(detail["duration_seconds"]) <= max_duration:
                    continue
                if args.commercial_only and not detail["commercial_compatible"]:
                    continue

                extension = ".ogg" if detail["preview_kind"] == "hq-ogg" else ".mp3"
                local_path = args.preview_dir / category["slug"] / f"freesound_{sound_id}{extension}"
                try:
                    preview_sha256 = (
                        hashlib.sha256(local_path.read_bytes()).hexdigest()
                        if local_path.exists()
                        else download(detail["preview_url"], local_path)
                    )
                except Exception as exc:
                    print(f"{category['slug']}: skip {sound_id}, preview error: {type(exc).__name__}", flush=True)
                    continue

                record = {
                    "source": "freesound_public_web",
                    "freesound_id": sound_id,
                    "category": category["slug"],
                    "category_name_zh": category["name_zh"],
                    "intended_use": category["intended_use"],
                    "query": category["query"],
                    "sound_url": sound_url,
                    **detail,
                    "attribution_text": f"{detail['name']} by {detail['username']} ({detail['license_code']})",
                    "local_path": str(local_path),
                    "preview_sha256": preview_sha256,
                    "downloaded_at": now_utc(),
                    "review_status": "pending",
                    "reviewed_class": "",
                    "contains_target_species": "",
                    "contains_speech": "",
                    "privacy_risk": "",
                    "valid_intervals": "",
                    "review_notes": "",
                    "collector_note": "Public HTML fallback; metadata must be rechecked before publication.",
                }
                records_by_id[sound_id] = record
                used_ids.add(sound_id)
                category_count += 1
                checkpoint_records = sorted(
                    records_by_id.values(),
                    key=lambda row: (str(row.get("category", "")), int(row["freesound_id"])),
                )
                write_records(checkpoint_records, jsonl_path, csv_path)
                print(f"{category['slug']}: downloaded {category_count}/{target} id={sound_id}", flush=True)
                if category_count >= target:
                    break
            if category_count >= target:
                break
        print(f"{category['slug']}: final {category_count}/{target}", flush=True)

    records = sorted(records_by_id.values(), key=lambda row: (str(row.get("category", "")), int(row["freesound_id"])))
    write_records(records, jsonl_path, csv_path)
    print(f"Candidates total: {len(records)}")
    print(f"Manifest: {csv_path.resolve()}")
    print("All candidates remain review_status=pending.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
