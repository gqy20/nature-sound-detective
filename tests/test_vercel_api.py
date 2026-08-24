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
    response = TestClient(cloud_api.app).get(
        "/api/health", headers={"X-Trace-ID": "rec_test_12345678"}
    )
    assert response.status_code == 200
    assert response.json()["mode"] == "vercel-qwen-only"
    assert response.headers["X-Trace-ID"] == "rec_test_12345678"


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
    assert payload["capabilities"]["investigation"] is True
    assert payload["investigation"]["status"] == "awaiting_observation"


def test_cloud_stateless_observation_uses_shared_transition(monkeypatch):
    monkeypatch.setattr(cloud_api, "_get_analyzer", lambda: FakeAnalyzer())
    wav_header = b"RIFF" + (b"\x00" * 4) + b"WAVE" + (b"\x00" * 40)
    analyzed = TestClient(cloud_api.app).post(
        "/api/analyze",
        files={"audio": ("recording.wav", wav_header, "audio/wav")},
        data={"location": "杭州"},
    ).json()
    investigation = analyzed["investigation"]
    response = TestClient(cloud_api.app).post(
        "/api/investigation/observations",
        json={
            "investigation": investigation,
            "question_id": investigation["question"]["id"],
            "choice": "observed",
            "note": "观察到了重复节奏",
        },
    )
    assert response.status_code == 200
    assert response.json()["status"] == "completed"
    assert response.json()["stop_reason"] == "human_observation_recorded"


def test_cloud_rejects_non_wav_upload():
    response = TestClient(cloud_api.app).post(
        "/api/analyze",
        files={"audio": ("recording.webm", b"not-a-wav", "audio/webm")},
    )
    assert response.status_code == 422
