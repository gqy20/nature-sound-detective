from scripts.validate_bioacoustic_models import validate


def test_checked_in_bioacoustic_model_contracts():
    report = validate()

    assert report["ok"] is True, report["errors"]
    assert report["birdnet"]["candidate_count"] == 200
    assert report["birdnet"]["output_shapes"] == [[1, 6522], [1, 1024]]
    assert report["nonbird"]["installed"] is False
