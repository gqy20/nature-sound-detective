from __future__ import annotations

import csv
from pathlib import Path

import pytest

from scripts.audit_nonbird_candidates import audit
from scripts.review_nonbird_candidates import CandidateReviewStore


def _candidate(path: Path) -> None:
    fields = [
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
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerow(
            {
                "source": "test",
                "source_id": "sound_1",
                "taxon_id": "polypedates_braueri",
                "name_zh": "布氏泛树蛙",
                "category_id": "frog",
                "license_code": "CC-BY-NC",
                "attribution": "Recorder",
                "split_group": "recording_1",
                "review_status": "pending",
            }
        )


def test_review_store_requires_reviewer_and_updates_label(tmp_path: Path):
    manifest = tmp_path / "candidates.csv"
    _candidate(manifest)
    store = CandidateReviewStore(manifest)
    with pytest.raises(ValueError, match="复核人"):
        store.update(
            {
                "source_id": "sound_1",
                "status": "human_reviewed",
                "taxon_id": "polypedates_braueri",
                "reviewer": "",
            }
        )
    saved = store.update(
        {
            "source_id": "sound_1",
            "status": "human_reviewed",
            "taxon_id": "other_frog",
            "reviewer": "reviewer-a",
            "valid_intervals": "1.0-4.5",
            "review_notes": "clear call",
        }
    )
    assert saved["name_zh"] == "其他蛙类"
    assert saved["review_status"] == "human_reviewed"


def test_audit_only_counts_reviewed_existing_audio_as_ready(tmp_path: Path):
    manifest = tmp_path / "candidates.csv"
    _candidate(manifest)
    report = audit([manifest])
    assert report["candidates"] == 1
    assert report["ready_for_training"] == 0
    assert report["by_taxon"] == {"polypedates_braueri": 1}
