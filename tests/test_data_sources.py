from pathlib import Path

from ml.data_sources.candidates import license_is_usable, normalize_license, write_candidates
from scripts.collect_inaturalist_sounds import observation_records
from scripts.select_insectset459 import select_rows


def test_license_normalization_rejects_unknown_and_no_derivatives():
    assert normalize_license("cc-by-nc")["license_code"] == "CC-BY-NC"
    assert normalize_license("https://creativecommons.org/publicdomain/zero/1.0/")["license_code"] == "CC0"
    assert license_is_usable("CC-BY-NC") is True
    assert license_is_usable("CC-BY-ND") is False
    assert license_is_usable("UNKNOWN") is False


def test_inaturalist_observation_expands_each_licensed_sound():
    observation = {
        "id": 42,
        "uri": "https://www.inaturalist.org/observations/42",
        "quality_grade": "research",
        "observed_on": "2026-07-01",
        "place_guess": "Hangzhou",
        "geojson": {"coordinates": [120.1, 30.2]},
        "sounds": [
            {
                "id": 7,
                "license_code": "cc-by-nc",
                "attribution": "Recorder (CC BY-NC)",
                "file_url": "https://example.test/7.m4a",
            }
        ],
    }
    rows = observation_records(
        observation,
        {
            "taxon_id": "polypedates_braueri",
            "scientific_name": "Polypedates braueri",
            "name_zh": "布氏泛树蛙",
            "category_id": "frog",
        },
        commercial_only=False,
    )
    assert rows[0]["source_id"] == "inat_42_7"
    assert rows[0]["latitude"] == 30.2
    assert rows[0]["review_status"] == "pending"


def test_insectset_selection_preserves_source_split_and_uses_other_insect(tmp_path: Path):
    annotation = tmp_path / "annotation.csv"
    annotation.write_text(
        "file_name,species_name,group,license,contributor,observation,file,background,original_name,subset,temperature\n"
        "cicada.mp3,Cicada_example,Cicadidae,http://creativecommons.org/licenses/by/4.0/,A,https://example.test/o,https://example.test/a.mp3,,,Test,\n"
        "cricket.mp3,Cricket_example,Orthoptera,http://creativecommons.org/licenses/by/4.0/,B,https://example.test/c,https://example.test/c.mp3,,,Train,\n",
        encoding="utf-8",
    )
    rows = select_rows(
        annotation,
        group="Cicadidae",
        species=set(),
        limit_per_species=20,
        commercial_only=False,
    )
    assert len(rows) == 1
    assert rows[0]["taxon_id"] == "other_insect"
    assert rows[0]["split_hint"] == "test"


def test_candidate_writer_has_stable_csv_and_jsonl(tmp_path: Path):
    output = tmp_path / "candidates.csv"
    rows = write_candidates(
        [{"source": "test", "source_id": "2", "taxon_id": "frog"}],
        output,
    )
    assert output.is_file()
    assert output.with_suffix(".jsonl").is_file()
    assert rows[0]["review_status"] == ""
