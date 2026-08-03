from __future__ import annotations

import csv
from pathlib import Path

from scripts.build_nonbird_training_manifest import (
    build_rows,
    deterministic_split,
    ensure_positive_split_coverage,
)
from scripts.import_curated_bioacoustics import load_curated_rows
from scripts.select_freesound_training_backgrounds import select_backgrounds


def _write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    fields = sorted({key for row in rows for key in row})
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def test_curated_import_requires_media_and_usable_license(tmp_path: Path):
    source = tmp_path / "curated.csv"
    _write_csv(
        source,
        [
            {
                "source": "museum",
                "source_id": "frog-1",
                "taxon_id": "polypedates_braueri",
                "name_zh": "布氏泛树蛙",
                "category_id": "frog",
                "source_url": "https://example.test/record",
                "media_url": "https://example.test/audio.wav",
                "license": "CC-BY-NC-SA-2.5",
                "attribution": "Recorder",
                "review_status": "pending",
            },
            {
                "source": "museum",
                "source_id": "frog-2",
                "taxon_id": "other_frog",
                "name_zh": "其他蛙类",
                "category_id": "frog",
                "source_url": "https://example.test/record2",
                "media_url": "",
                "license": "unknown",
                "attribution": "Recorder",
                "review_status": "pending",
            },
        ],
    )
    rows, warnings = load_curated_rows(source, commercial_only=False)
    assert len(rows) == 1
    assert rows[0]["license_code"] == "CC-BY-NC-SA"
    assert warnings


def test_freesound_adapter_only_accepts_reviewed_background_without_speech(tmp_path: Path):
    source = tmp_path / "freesound.csv"
    _write_csv(
        source,
        [
            {
                "freesound_id": "1",
                "review_status": "human_reviewed",
                "human_final_class": "background",
                "human_contains_speech": "no",
                "license": "CC-BY",
                "local_path": "audio.mp3",
            },
            {
                "freesound_id": "2",
                "review_status": "human_reviewed",
                "human_final_class": "background",
                "human_contains_speech": "yes",
                "license": "CC-BY",
                "local_path": "speech.mp3",
            },
        ],
    )
    rows = select_backgrounds(source, commercial_only=False)
    assert [row["source_id"] for row in rows] == ["freesound_1"]


def test_freesound_source_labels_can_be_trusted_explicitly(tmp_path: Path):
    source = tmp_path / "freesound.csv"
    _write_csv(
        source,
        [
            {
                "freesound_id": "1",
                "review_status": "machine_labeled_needs_listening",
                "intended_use": "background",
                "contains_speech": "unlikely",
                "license": "CC-BY",
                "local_path": "audio.mp3",
            }
        ],
    )
    rows = select_backgrounds(
        source,
        commercial_only=False,
        trust_source_labels=True,
    )
    assert rows[0]["review_status"] == "source_curated"


def test_manifest_builder_excludes_pending_and_preserves_group_split(tmp_path: Path):
    audio = tmp_path / "frog.wav"
    audio.write_bytes(b"RIFF-test")
    candidates = tmp_path / "candidates.csv"
    _write_csv(
        candidates,
        [
            {
                "source": "test",
                "source_id": "approved",
                "taxon_id": "polypedates_braueri",
                "local_path": str(audio),
                "license_code": "CC-BY-NC",
                "commercial_compatible": "false",
                "review_status": "human_reviewed",
                "split_group": "same-recording",
                "split_hint": "test",
            },
            {
                "source": "test",
                "source_id": "approved-train",
                "taxon_id": "polypedates_braueri",
                "local_path": str(audio),
                "license_code": "CC-BY-NC",
                "commercial_compatible": "false",
                "review_status": "human_reviewed",
                "split_group": "train-recording",
                "split_hint": "train",
            },
            {
                "source": "test",
                "source_id": "approved-validation",
                "taxon_id": "polypedates_braueri",
                "local_path": str(audio),
                "license_code": "CC-BY-NC",
                "commercial_compatible": "false",
                "review_status": "human_reviewed",
                "split_group": "validation-recording",
                "split_hint": "validation",
            },
            {
                "source": "test",
                "source_id": "pending",
                "taxon_id": "polypedates_braueri",
                "local_path": str(audio),
                "review_status": "pending",
                "split_group": "other",
            },
        ],
    )
    rows = build_rows([candidates], output=tmp_path / "manifest.csv", commercial_only=False)
    assert len(rows) == 3
    assert {row["split"] for row in rows} == {"train", "validation", "test"}
    assert {row["labels"] for row in rows} == {"polypedates_braueri"}
    assert deterministic_split("same-recording") == deterministic_split("same-recording")


def test_source_split_coverage_moves_only_unlocked_groups():
    rows = [
        {
            "labels": "frog",
            "split": "train",
            "split_group": f"group-{index}",
            "_split_locked": "false",
        }
        for index in range(4)
    ]
    ensure_positive_split_coverage(rows)
    assert {row["split"] for row in rows} == {"train", "validation", "test"}
