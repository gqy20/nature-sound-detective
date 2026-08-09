from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

import app.community.routes as community_routes
from app.community.repository import MemoryCommunityRepository


def _client(tmp_path, monkeypatch) -> TestClient:
    monkeypatch.setattr(community_routes, "COMMUNITY_MEDIA_DIR", tmp_path)
    app = FastAPI()
    app.include_router(
        community_routes.build_community_router(MemoryCommunityRepository())
    )
    return TestClient(app)


def _metadata(**overrides):
    value = {
        "owner_id": "device_owner_123456",
        "alias": "雾林探员 027",
        "area_id": "xihu",
        "area_name": "西湖区",
        "subject": "乌鸫候选",
        "sound_type": "鸟鸣",
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "duration_ms": 8_000,
        "candidate_names": ["乌鸫", "鹊鸲"],
        "field_observations": ["声音来自树冠", "节奏有规律"],
        "model_snapshot": {"birdnet": "2.4"},
        "adult_confirmed": True,
        "public_consent": True,
        "review_consent": False,
    }
    value.update(overrides)
    return value


def test_publish_assist_and_withdraw(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    created = client.post(
        "/api/community/posts",
        data={"metadata": json.dumps(_metadata(), ensure_ascii=False)},
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert created.status_code == 201
    post = created.json()["post"]
    assert post["area_name"] == "西湖区"
    assert post["owned_by_requester"] is True
    assert post["status"] == "published_unverified"

    listed = client.get(
        "/api/community/posts", headers={"X-Device-ID": "device_owner_123456"}
    )
    assert listed.json()[0]["owned_by_requester"] is True

    assisted = client.post(
        f"/api/community/posts/{post['id']}/responses",
        json={
            "responder_id": "device_helper_123456",
            "choice": "乌鸫",
            "also_heard": True,
            "key_second": 4,
        },
    )
    assert assisted.status_code == 200
    assert assisted.json()["response_summary"] == {"乌鸫": 1}

    denied = client.delete(
        f"/api/community/posts/{post['id']}",
        headers={"X-Device-ID": "device_wrong_123456"},
    )
    assert denied.status_code == 404
    withdrawn = client.delete(
        f"/api/community/posts/{post['id']}",
        headers={"X-Device-ID": "device_owner_123456"},
    )
    assert withdrawn.status_code == 204
    assert list(tmp_path.iterdir()) == []
    assert client.get("/api/community/posts").json() == []


def test_publish_requires_adult_public_consent(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        data={
            "metadata": json.dumps(
                _metadata(adult_confirmed=False), ensure_ascii=False
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 403
    assert list(tmp_path.iterdir()) == []


def test_area_summary_keeps_empty_hangzhou_regions(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    areas = client.get("/api/community/areas")
    assert areas.status_code == 200
    assert len(areas.json()) == 6
    assert {item["area_id"] for item in areas.json()} >= {"xihu", "binjiang"}
