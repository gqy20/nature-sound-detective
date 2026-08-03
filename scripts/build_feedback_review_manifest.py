from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, Iterable

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import CANDIDATE_FIELDS
from ml.nonbird.config import load_nonbird_config


def payloads(path: Path) -> Iterable[tuple[dict[str, Any], Path]]:
    if path.is_dir():
        for child in sorted(path.glob("*.json")):
            yield json.loads(child.read_text(encoding="utf-8")), child.parent
        return
    if path.suffix.lower() == ".jsonl":
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                yield json.loads(line), path.parent
        return
    yield json.loads(path.read_text(encoding="utf-8")), path.parent


def audio_path(payload: dict[str, Any], base: Path) -> Path | None:
    value = payload.get("retained_audio_path") or payload.get("audio_path")
    if not value:
        return None
    path = Path(str(value))
    return path if path.is_absolute() else (base / path).resolve()


def proposed_taxon(payload: dict[str, Any], known: set[str]) -> str:
    feedback = payload.get("feedback") if isinstance(payload.get("feedback"), dict) else payload
    corrected = str(feedback.get("corrected_taxon_id") or "")
    if corrected in known:
        return corrected
    detections = payload.get("prediction_snapshot") or payload.get("detections") or []
    for detection in detections:
        species = detection.get("specific_species") if isinstance(detection, dict) else None
        taxon_id = species.get("taxonomy_id") if isinstance(species, dict) else None
        if taxon_id in known:
            return str(taxon_id)
    return "background"


def build_rows(inputs: list[Path]) -> list[dict[str, str]]:
    config = load_nonbird_config()
    classes = {item.taxon_id: item for item in config.classes}
    rows: list[dict[str, str]] = []
    seen_hashes: set[str] = set()
    for source in inputs:
        for payload, base in payloads(source):
            feedback = payload.get("feedback") if isinstance(payload.get("feedback"), dict) else payload
            if not feedback.get("consent_to_retain_audio"):
                continue
            local = audio_path(payload, base)
            if local is None or not local.is_file():
                continue
            digest = hashlib.sha256(local.read_bytes()).hexdigest()
            if digest in seen_hashes:
                continue
            seen_hashes.add(digest)
            taxon_id = proposed_taxon(payload, set(classes))
            item = classes[taxon_id]
            source_id = str(payload.get("id") or payload.get("recording_id") or digest[:16])
            row = {field: "" for field in CANDIDATE_FIELDS}
            row.update(
                {
                    "source": "user_feedback",
                    "source_id": source_id,
                    "taxon_id": taxon_id,
                    "scientific_name": item.scientific_name or "",
                    "name_zh": item.name_zh,
                    "category_id": item.category_id,
                    "license_code": "USER-CONSENT",
                    "commercial_compatible": "false",
                    "attribution": "private user contribution",
                    "quality_grade": "user_reported",
                    "locality": str(payload.get("location") or "杭州"),
                    "split_group": f"feedback:{payload.get('recording_id') or source_id}",
                    "local_path": str(local.resolve()),
                    "sha256": digest,
                    "review_status": "pending",
                    "review_notes": f"user decision: {feedback.get('decision', 'uncertain')}",
                }
            )
            rows.append(row)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="将已同意留存的端云反馈转换为人工复核候选")
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/metadata/nonbird_feedback_review_candidates.csv"),
    )
    args = parser.parse_args()
    rows = build_rows(args.inputs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CANDIDATE_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows)} consented feedback candidates to {args.output}")


if __name__ == "__main__":
    main()
