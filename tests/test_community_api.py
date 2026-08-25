from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

import app.community.routes as community_routes
from app.community.auth import CommunityAuth
from app.community.repository import MemoryCommunityRepository
from app.community.storage import LocalCommunityMediaStore


def _client(tmp_path, monkeypatch) -> TestClient:
    monkeypatch.setattr(community_routes, "COMMUNITY_MEDIA_DIR", tmp_path)
    app = FastAPI()
    app.include_router(
        community_routes.build_community_router(
            MemoryCommunityRepository(),
            media_store=LocalCommunityMediaStore(tmp_path),
            auth=CommunityAuth("test-community-secret-with-32-characters"),
        )
    )
    return TestClient(app)


def _headers(client: TestClient, device_id: str) -> dict[str, str]:
    response = client.post(
        "/api/community/session",
        json={"device_id": device_id},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['token']}"}


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
    owner_headers = _headers(client, "device_owner_123456")
    created = client.post(
        "/api/community/posts",
        headers=owner_headers,
        data={"metadata": json.dumps(_metadata(), ensure_ascii=False)},
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert created.status_code == 201
    post = created.json()["post"]
    assert post["area_name"] == "西湖区"
    assert post["owned_by_requester"] is True
    assert post["status"] == "published_unverified"

    media = client.post(
        f"/api/community/posts/{post['id']}/media",
        headers=owner_headers,
        data={
            "media_type": "image",
            "source_type": "ai_generated",
            "provider": "story-card",
        },
        files={"file": ("postcard.png", b"\x89PNG" + b"1" * 64, "image/png")},
    )
    assert media.status_code == 201
    assert media.json()["source_type"] == "ai_generated"

    listed = client.get("/api/community/posts", headers=owner_headers)
    assert listed.json()[0]["owned_by_requester"] is True
    assert listed.json()[0]["media_assets"][0]["media_type"] == "image"

    assisted = client.post(
        f"/api/community/posts/{post['id']}/responses",
        headers=_headers(client, "device_helper_123456"),
        json={
            "responder_id": "device_spoofed_123456",
            "choice": "乌鸫",
            "also_heard": True,
            "key_second": 4,
        },
    )
    assert assisted.status_code == 200
    assert assisted.json()["response_summary"] == {"乌鸫": 1}

    denied = client.delete(
        f"/api/community/posts/{post['id']}",
        headers=_headers(client, "device_wrong_123456"),
    )
    assert denied.status_code == 404
    withdrawn = client.delete(
        f"/api/community/posts/{post['id']}",
        headers=owner_headers,
    )
    assert withdrawn.status_code == 204
    assert list(tmp_path.iterdir()) == []
    assert client.get("/api/community/posts").json() == []


def test_publish_requires_adult_public_consent(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_owner_123456"),
        data={
            "metadata": json.dumps(
                _metadata(adult_confirmed=False), ensure_ascii=False
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 403
    assert list(tmp_path.iterdir()) == []


def test_write_operations_require_a_valid_bearer_token(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers={"Authorization": "Bearer invalid"},
        data={"metadata": json.dumps(_metadata(), ensure_ascii=False)},
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert list(tmp_path.iterdir()) == []


def test_area_summary_keeps_empty_hangzhou_regions(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    areas = client.get("/api/community/areas")
    assert areas.status_code == 200
    assert len(areas.json()) == 6
    assert {item["area_id"] for item in areas.json()} >= {"xihu", "binjiang"}


def test_pilot_parks_sites_and_ecology_snapshot(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    parks = client.get("/api/community/parks")
    assert parks.status_code == 200
    assert {item["park_id"] for item in parks.json()} == {
        "hangzhou-botanical-garden", "xixi-wetland", "taiziwan-park"
    }
    sites = client.get(
        "/api/community/sites", params={"park_id": "hangzhou-botanical-garden"}
    )
    assert sites.status_code == 200
    assert len(sites.json()) == 3
    snapshot = client.get(
        "/api/community/parks/hangzhou-botanical-garden/ecology-snapshot"
    )
    assert snapshot.status_code == 200
    assert snapshot.json()["data_sufficiency"] == "low"
    assert "不替代专业生态监测" in snapshot.json()["disclaimer"]
    brief = client.get(
        "/api/community/parks/hangzhou-botanical-garden/daily-brief"
    )
    assert brief.status_code == 200
    assert "等待更多声音" in brief.json()["headline"]
    assert brief.json()["data_sufficiency"] == "low"
    routes = client.get(
        "/api/community/parks/hangzhou-botanical-garden/routes"
    )
    assert routes.status_code == 200
    assert routes.json()[0]["name"] == "清晨树冠声音路线"
    assert len(routes.json()[0]["stops"]) == 3
    assert "不保证一定遇见动物" in routes.json()[0]["disclaimer"]


def test_park_publication_is_validated_and_ecology_eligible(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    headers = _headers(client, "device_owner_park_123456")
    metadata = _metadata(
        park_id="hangzhou-botanical-garden",
        zone_id="understory-trail",
        audio_quality={"usable": True, "rms": 0.08},
        sampling_mode="guided_task",
        sampling_effort={"duration_seconds": 8},
    )
    created = client.post(
        "/api/community/posts",
        headers=headers,
        data={"metadata": json.dumps(metadata, ensure_ascii=False)},
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert created.status_code == 201
    post = created.json()["post"]
    assert post["park_id"] == "hangzhou-botanical-garden"
    assert post["site_id"] == "hangzhou-botanical-garden:understory-trail"
    assert post["ecology_eligible"] is True
    snapshot = client.get(
        "/api/community/parks/hangzhou-botanical-garden/ecology-snapshot"
    ).json()
    assert snapshot["valid_post_count"] == 1
    assert snapshot["independent_observer_count"] == 1
    assert snapshot["observation_day_count"] == 1
    assert snapshot["activity_trend"] == "insufficient"
    assert len(snapshot["zone_summaries"]) == 3


def test_weak_audio_can_be_published_but_does_not_count_as_ecology(
    tmp_path, monkeypatch
):
    client = _client(tmp_path, monkeypatch)
    metadata = _metadata(
        park_id="hangzhou-botanical-garden",
        zone_id="understory-trail",
        audio_quality={
            "usable": True,
            "weak_signal": True,
            "ecology_usable": False,
        },
    )
    created = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_owner_weak_audio_123456"),
        data={"metadata": json.dumps(metadata, ensure_ascii=False)},
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )

    assert created.status_code == 201
    assert created.json()["post"]["ecology_eligible"] is False
    snapshot = client.get(
        "/api/community/parks/hangzhou-botanical-garden/ecology-snapshot"
    ).json()
    assert snapshot["valid_post_count"] == 0


def test_invalid_park_zone_combination_is_rejected(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_owner_invalid_123456"),
        data={
            "metadata": json.dumps(
                _metadata(
                    park_id="hangzhou-botanical-garden",
                    zone_id="not-a-zone",
                    audio_quality={"usable": True},
                ),
                ensure_ascii=False,
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 422


def test_explicit_catalog_site_id_is_accepted(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_owner_site_id_123456"),
        data={
            "metadata": json.dumps(
                _metadata(
                    park_id="hangzhou-botanical-garden",
                    zone_id="understory-trail",
                    site_id="hangzhou-botanical-garden:understory-trail",
                    audio_quality={"usable": True},
                ),
                ensure_ascii=False,
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 201
    assert (
        response.json()["post"]["site_id"]
        == "hangzhou-botanical-garden:understory-trail"
    )


def test_mismatched_site_id_is_rejected(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_owner_wrong_site_123456"),
        data={
            "metadata": json.dumps(
                _metadata(
                    park_id="hangzhou-botanical-garden",
                    zone_id="understory-trail",
                    site_id="xixi-wetland:reed-edge",
                    audio_quality={"usable": True},
                ),
                ensure_ascii=False,
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 422
    assert response.json()["detail"] == "观察点与公园分区不一致"


def test_demo_post_can_show_on_park_map_but_never_counts_as_ecology(tmp_path, monkeypatch):
    client = _client(tmp_path, monkeypatch)
    response = client.post(
        "/api/community/posts",
        headers=_headers(client, "device_demo_park_123456"),
        data={
            "metadata": json.dumps(
                _metadata(
                    park_id="hangzhou-botanical-garden",
                    zone_id="understory-trail",
                    model_snapshot={"demo": True},
                    audio_quality={"usable": True},
                ),
                ensure_ascii=False,
            )
        },
        files={"audio": ("clip.wav", b"RIFF" + b"0" * 64, "audio/wav")},
    )
    assert response.status_code == 201
    assert response.json()["post"]["ecology_eligible"] is False
    snapshot = client.get(
        "/api/community/parks/hangzhou-botanical-garden/ecology-snapshot"
    )
    assert snapshot.json()["valid_post_count"] == 0
