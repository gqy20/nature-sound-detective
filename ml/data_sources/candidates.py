from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import time
from typing import Any, Iterable
import urllib.request


CANDIDATE_FIELDS = (
    "source",
    "source_id",
    "taxon_id",
    "scientific_name",
    "name_zh",
    "category_id",
    "source_url",
    "media_url",
    "license_code",
    "license_url",
    "commercial_compatible",
    "attribution",
    "quality_grade",
    "observed_on",
    "latitude",
    "longitude",
    "locality",
    "split_hint",
    "split_group",
    "local_path",
    "sha256",
    "review_status",
    "reviewer",
    "valid_intervals",
    "review_notes",
)


def normalize_license(value: str | None) -> dict[str, str | bool]:
    raw = (value or "").strip()
    compact = raw.lower().replace("_", "-")
    mappings = (
        (("cc0", "/zero/", "publicdomain/zero"), "CC0", True),
        (("by-nc-sa",), "CC-BY-NC-SA", False),
        (("by-nc-nd",), "CC-BY-NC-ND", False),
        (("by-nc",), "CC-BY-NC", False),
        (("by-sa",), "CC-BY-SA", True),
        (("by-nd",), "CC-BY-ND", True),
        (("cc-by", "/by/"), "CC-BY", True),
    )
    for markers, code, commercial in mappings:
        if any(marker in compact for marker in markers):
            return {
                "license_code": code,
                "license_url": raw,
                "commercial_compatible": commercial,
            }
    return {
        "license_code": "UNKNOWN",
        "license_url": raw,
        "commercial_compatible": False,
    }


def license_is_usable(code: str) -> bool:
    return code not in {"UNKNOWN", "CC-BY-ND", "CC-BY-NC-ND"}


def download_file(url: str, destination: Path, retries: int = 3) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "nature-sound-detective-research/0.1"},
    )
    for attempt in range(retries):
        digest = hashlib.sha256()
        try:
            with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as handle:
                while chunk := response.read(1024 * 1024):
                    handle.write(chunk)
                    digest.update(chunk)
            os.replace(partial, destination)
            return digest.hexdigest()
        except Exception:
            if attempt + 1 >= retries:
                raise
            time.sleep(2**attempt)
    raise RuntimeError(f"download failed: {url}")


def _replace_with_retries(source: Path, destination: Path, retries: int = 5) -> None:
    for attempt in range(retries):
        try:
            os.replace(source, destination)
            return
        except OSError:
            if attempt + 1 >= retries:
                raise
            time.sleep(0.1 * (attempt + 1))


def write_candidates(records: Iterable[dict[str, Any]], output: Path) -> list[dict[str, Any]]:
    rows = sorted(
        ({field: row.get(field, "") for field in CANDIDATE_FIELDS} for row in records),
        key=lambda row: (str(row["taxon_id"]), str(row["source_id"])),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    csv_temporary = output.with_suffix(output.suffix + ".tmp")
    with csv_temporary.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CANDIDATE_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    _replace_with_retries(csv_temporary, output)
    jsonl = output.with_suffix(".jsonl")
    jsonl_temporary = jsonl.with_suffix(jsonl.suffix + ".tmp")
    jsonl_temporary.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )
    _replace_with_retries(jsonl_temporary, jsonl)
    return rows


def mark_duplicate_audio(records: list[dict[str, Any]]) -> int:
    seen: dict[str, str] = {}
    duplicates = 0
    for row in records:
        digest = str(row.get("sha256", "")).strip()
        if not digest:
            continue
        if digest in seen:
            row["review_status"] = "duplicate"
            row["review_notes"] = f"duplicate_of:{seen[digest]}"
            duplicates += 1
        else:
            seen[digest] = str(row.get("source_id", ""))
    return duplicates
