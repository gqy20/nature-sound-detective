from pathlib import Path
import wave

import numpy as np

from scripts.evaluate_multibird_mixtures import (
    SAMPLE_RATE,
    aggregate_predictions,
    build_scenarios,
    load_candidate_labels,
    mix_tracks,
    read_pcm16_mono,
    score_clip,
    write_pcm16_mono,
)


def test_scenario_matrix_balances_each_species_as_primary():
    species = ["甲", "乙", "丙", "丁", "戊"]
    scenarios = build_scenarios(species)

    assert len(scenarios) == len(species) * 5
    assert {row["scenario"] for row in scenarios} == {
        "overlap_equal",
        "overlap_secondary_minus_6db",
        "overlap_secondary_minus_12db",
        "sequential_equal",
        "overlap_three_equal",
    }
    assert [row["species"][0] for row in scenarios].count("甲") == 5


def test_candidate_labels_include_complete_mobile_catalog(tmp_path: Path):
    path = tmp_path / "labels.json"
    path.write_text(
        '{"species": ['
        '{"scientific_name": "Birdus one", "name_en": "One", "name_zh": "甲"},'
        '{"scientific_name": "Birdus two", "name_en": "Two", "name_zh": "乙"}'
        "]}",
        encoding="utf-8",
    )

    labels, names = load_candidate_labels(path)

    assert labels == ["Birdus one_One", "Birdus two_Two"]
    assert names["Birdus two_Two"] == "乙"


def test_mix_tracks_applies_relative_gain_and_sequential_layout():
    first = np.ones(8, dtype=np.float32)
    second = np.ones(8, dtype=np.float32)

    overlapped = mix_tracks([first, second], [0.0, -6.0])
    sequential = mix_tracks([first * 0.2, second * 0.1], [0.0, 0.0], sequential=True)

    # The overlap is peak-normalized, but both inputs still contribute.
    assert np.allclose(overlapped, 0.98)
    assert np.allclose(sequential[:8], 0.2)
    assert np.allclose(sequential[8:], 0.1)


def test_pcm_round_trip_is_mono_48k_and_pads_segment(tmp_path: Path):
    path = tmp_path / "sample.wav"
    samples = np.linspace(-0.5, 0.5, SAMPLE_RATE, dtype=np.float32)
    write_pcm16_mono(path, samples)

    result = read_pcm16_mono(path, start_seconds=0.5, duration_seconds=1.0)

    with wave.open(str(path), "rb") as handle:
        assert handle.getnchannels() == 1
        assert handle.getframerate() == SAMPLE_RATE
    assert len(result) == SAMPLE_RATE
    assert np.count_nonzero(result[SAMPLE_RATE // 2 :]) == 0


def test_aggregation_and_scoring_mirror_threshold_then_top_three():
    rows = [
        {"species_name": "bird-a", "confidence": 0.2, "start_time": 0.0, "end_time": 3.0},
        {"species_name": "bird-a", "confidence": 0.7, "start_time": 3.0, "end_time": 6.0},
        {"species_name": "bird-b", "confidence": 0.04, "start_time": 0.0, "end_time": 3.0},
        {"species_name": "bird-c", "confidence": 0.6, "start_time": 0.0, "end_time": 3.0},
        {"species_name": "bird-d", "confidence": 0.5, "start_time": 0.0, "end_time": 3.0},
        {"species_name": "bird-e", "confidence": 0.4, "start_time": 0.0, "end_time": 3.0},
    ]

    ranked = aggregate_predictions(rows)
    score = score_clip(["bird-a", "bird-b", "bird-e"], ranked, threshold=0.05)

    assert ranked[0]["label"] == "bird-a"
    assert ranked[0]["confidence"] == 0.7
    assert score["hit_count"] == 1
    assert score["all_expected_displayed"] is False
    assert score["false_positive_count"] == 2
