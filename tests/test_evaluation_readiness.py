from app.evaluation_readiness import readiness_report


def test_readiness_counts_only_verified_included_samples():
    rows = [
        {"expected_sound_types": "雨水|流水", "expected_species": "", "label_status": "verified", "include": "yes"},
        {"expected_sound_types": "雨水", "expected_species": "", "label_status": "weak", "include": "yes"},
        {"expected_sound_types": "鸟类鸣叫", "expected_species": "乌鸫", "label_status": "verified", "include": "yes"},
        {"expected_sound_types": "鸟类鸣叫", "expected_species": "乌鸫", "label_status": "verified", "include": "no"},
    ]
    report = readiness_report(rows, ["乌鸫"], sound_minimum=1, species_minimum=1)
    assert report["sound_types"]["雨水/流水"] == {"verified": 1, "weak": 1, "included": 2, "target": 1, "gap": 0}
    assert report["species"]["乌鸫"]["verified"] == 1
    assert report["species"]["乌鸫"]["included"] == 1
    assert report["species_ready"] is True
    assert report["formal_evaluation_ready"] is False
