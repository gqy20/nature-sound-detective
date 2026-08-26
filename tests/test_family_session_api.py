from __future__ import annotations

from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.community.auth import CommunityAuth
from app.family_sessions.repository import MemoryFamilySessionRepository
from app.family_sessions.routes import build_family_session_router


AUTH = CommunityAuth("family-session-test-secret-that-is-long-enough")


def _headers(device_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {AUTH.issue(device_id).token}"}


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(
        build_family_session_router(
            MemoryFamilySessionRepository(),
            auth=AUTH,
        )
    )
    return TestClient(app)


def test_two_device_pairing_event_sync_and_command_flow():
    client = _client()
    parent = _headers("device_family_parent_123456")
    child = _headers("device_family_child_123456")

    created = client.post("/api/family-sessions", headers=parent)
    assert created.status_code == 201
    session_id = created.json()["session_id"]
    pair_code = created.json()["pair_code"]
    assert created.json()["status"] == "waiting_for_child"
    assert len(pair_code) == 6

    joined = client.post(
        "/api/family-sessions/join",
        headers=child,
        json={"pair_code": pair_code},
    )
    assert joined.status_code == 200
    assert joined.json()["role"] == "child"
    assert joined.json()["status"] == "pending_approval"

    before_approval = client.post(
        f"/api/family-sessions/{session_id}/events/batch",
        headers=child,
        json={"events": [_event(1, "replayed_audio")]},
    )
    assert before_approval.status_code == 409

    approved = client.post(
        f"/api/family-sessions/{session_id}/approve",
        headers=parent,
    )
    assert approved.status_code == 200
    assert approved.json()["status"] == "active"

    uploaded = client.post(
        f"/api/family-sessions/{session_id}/events/batch",
        headers=child,
        json={
            "events": [
                _event(1, "captured_sound"),
                _event(2, "replayed_audio"),
                _event(3, "accepted_uncertainty"),
            ]
        },
    )
    assert uploaded.status_code == 200
    assert uploaded.json() == {"accepted": 3, "last_sequence": 3}

    repeated = client.post(
        f"/api/family-sessions/{session_id}/events/batch",
        headers=child,
        json={"events": [_event(2, "replayed_audio")]},
    )
    assert repeated.status_code == 200
    assert repeated.json()["accepted"] == 0

    events = client.get(
        f"/api/family-sessions/{session_id}/events?after_sequence=1",
        headers=parent,
    )
    assert events.status_code == 200
    assert [item["event_type"] for item in events.json()] == [
        "replayed_audio",
        "accepted_uncertainty",
    ]

    forbidden = client.get(
        f"/api/family-sessions/{session_id}/events",
        headers=child,
    )
    assert forbidden.status_code == 403

    command = client.post(
        f"/api/family-sessions/{session_id}/commands",
        headers=parent,
        json={"template_id": "compare_high_low_sound"},
    )
    assert command.status_code == 201
    commands = client.get(
        f"/api/family-sessions/{session_id}/commands",
        headers=child,
    )
    assert commands.status_code == 200
    assert commands.json()[0]["template_id"] == "compare_high_low_sound"

    ended = client.post(
        f"/api/family-sessions/{session_id}/end",
        headers=parent,
    )
    assert ended.status_code == 204
    status = client.get(
        f"/api/family-sessions/{session_id}",
        headers=child,
    )
    assert status.json()["status"] == "ended"


def test_pair_code_is_one_time_scoped_and_parent_cannot_join_own_session():
    client = _client()
    parent = _headers("device_family_parent_second_123")
    child = _headers("device_family_child_second_1234")
    created = client.post("/api/family-sessions", headers=parent).json()

    own_join = client.post(
        "/api/family-sessions/join",
        headers=parent,
        json={"pair_code": created["pair_code"]},
    )
    assert own_join.status_code == 409

    invalid = client.post(
        "/api/family-sessions/join",
        headers=child,
        json={"pair_code": "000000"},
    )
    assert invalid.status_code == 404


def _event(sequence: int, event_type: str) -> dict[str, object]:
    return {
        "event_id": f"evt_test_event_{sequence:08d}",
        "sequence": sequence,
        "event_type": event_type,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "payload": {"source": "test"},
    }
