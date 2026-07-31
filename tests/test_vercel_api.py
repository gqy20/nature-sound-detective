from fastapi.testclient import TestClient

import api.index as cloud_api


class FakeAnalyzer:
    def analyze(self, _path, _location):
        return {
            "sound_types": ["风和树叶"],
            "primary_sound_type": "风和树叶",
            "confidence_level": "medium",
            "evidence": ["连续沙沙声"],
            "model": "fake-qwen",
        }


def test_cloud_health():
    response = TestClient(cloud_api.app).get("/api/health")
    assert response.status_code == 200
    assert response.json()["mode"] == "vercel-qwen-only"


def test_cloud_analysis_returns_completed_job(monkeypatch):
    monkeypatch.setattr(cloud_api, "_get_analyzer", lambda: FakeAnalyzer())
    wav_header = b"RIFF" + (b"\x00" * 4) + b"WAVE" + (b"\x00" * 40)
    response = TestClient(cloud_api.app).post(
        "/api/analyze",
        files={"audio": ("recording.wav", wav_header, "audio/wav")},
        data={"location": "杭州"},
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "completed"
    assert payload["result"]["primary_sound_type"] == "风和树叶"
    assert payload["capabilities"]["birdnet"] is False
    assert payload["capabilities"]["creation"] is False


def test_cloud_rejects_non_wav_upload():
    response = TestClient(cloud_api.app).post(
        "/api/analyze",
        files={"audio": ("recording.webm", b"not-a-wav", "audio/webm")},
    )
    assert response.status_code == 422
