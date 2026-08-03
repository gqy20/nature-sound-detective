from scripts.prepare_nonbird_training_audio import destination_name


def test_prepared_audio_name_is_stable_and_safe():
    row = {
        "source_dataset": "iNaturalist",
        "source_recording_id": "inat:42/7",
    }
    first = destination_name(row)
    assert first == destination_name(row)
    assert first.startswith("inat_42_7_")
    assert first.endswith(".wav")
