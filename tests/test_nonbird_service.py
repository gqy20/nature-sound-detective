from pathlib import Path

from app.nonbird_service import NonBirdAnalyzer


def test_nonbird_analyzer_reports_unavailable_without_trained_artifacts(tmp_path: Path):
    analyzer = NonBirdAnalyzer(model_dir=tmp_path)

    result = analyzer.analyze(tmp_path / "unused.wav")

    assert result["available"] is False
    assert result["detections"] == []
    assert "unavailable" in result["model"]
