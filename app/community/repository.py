from __future__ import annotations

import hashlib
import json
import os
from collections import Counter
from threading import RLock
from typing import Any, Protocol
from uuid import uuid4

from app.community.models import (
    AREA_NAMES,
    AreaSummary,
    AssistSubmission,
    CommunityPost,
    PublicationMetadata,
    utc_now,
)


def _identity_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _database_url_from_environment() -> str:
    """Normalize secrets copied from files or deployment dashboards.

    A UTF-8 BOM can survive PowerShell pipelines and is not removed by
    ``str.strip()``. Psycopg then interprets the entire URL as an option name.
    """
    return os.getenv("DATABASE_URL", "").strip().lstrip("\ufeff").strip()


class CommunityRepository(Protocol):
    def list_posts(self, *, area_id: str | None, requester_id: str | None) -> list[CommunityPost]: ...
    def get_post(self, post_id: str, *, requester_id: str | None) -> CommunityPost | None: ...
    def area_summaries(self) -> list[AreaSummary]: ...
    def create_post(self, metadata: PublicationMetadata, audio_url: str) -> CommunityPost: ...
    def add_response(self, post_id: str, submission: AssistSubmission) -> CommunityPost | None: ...
    def withdraw(self, post_id: str, owner_id: str) -> bool: ...


class MemoryCommunityRepository:
    """Deterministic fallback for tests and offline competition rehearsals."""

    def __init__(self) -> None:
        self._posts: dict[str, dict[str, Any]] = {}
        self._responses: dict[str, dict[str, AssistSubmission]] = {}
        self._lock = RLock()

    def list_posts(self, *, area_id: str | None = None, requester_id: str | None = None) -> list[CommunityPost]:
        with self._lock:
            rows = [row for row in self._posts.values() if row["status"] != "withdrawn"]
            if area_id:
                rows = [row for row in rows if row["area_id"] == area_id]
            rows.sort(key=lambda row: row["created_at"], reverse=True)
            return [self._public(row, requester_id) for row in rows]

    def get_post(self, post_id: str, *, requester_id: str | None = None) -> CommunityPost | None:
        with self._lock:
            row = self._posts.get(post_id)
            if row is None or row["status"] == "withdrawn":
                return None
            return self._public(row, requester_id)

    def area_summaries(self) -> list[AreaSummary]:
        posts = self.list_posts(area_id=None, requester_id=None)
        grouped: dict[str, list[CommunityPost]] = {key: [] for key in AREA_NAMES}
        for post in posts:
            grouped.setdefault(post.area_id, []).append(post)
        return [
            AreaSummary(
                area_id=area_id,
                area_name=AREA_NAMES[area_id],
                post_count=len(items),
                waiting_count=sum(item.response_count == 0 for item in items),
                sound_types=list(dict.fromkeys(item.sound_type for item in items))[:2],
            )
            for area_id, items in grouped.items()
        ]

    def create_post(self, metadata: PublicationMetadata, audio_url: str) -> CommunityPost:
        if not metadata.adult_confirmed or not metadata.public_consent:
            raise PermissionError("公开发布需要成年人确认和独立公开授权")
        post_id = uuid4().hex
        row = {
            "id": post_id,
            "owner_hash": _identity_hash(metadata.owner_id),
            "alias": metadata.alias,
            "area_id": metadata.area_id,
            "area_name": metadata.area_name,
            "subject": metadata.subject,
            "sound_type": metadata.sound_type,
            "observed_at": metadata.observed_at,
            "created_at": utc_now(),
            "audio_url": audio_url,
            "duration_ms": metadata.duration_ms,
            "candidate_names": list(metadata.candidate_names),
            "field_observations": list(metadata.field_observations),
            "status": "published_unverified",
            "review_status": "queued" if metadata.review_consent else "not_requested",
        }
        with self._lock:
            self._posts[post_id] = row
            self._responses[post_id] = {}
        return self._public(row, metadata.owner_id)

    def add_response(self, post_id: str, submission: AssistSubmission) -> CommunityPost | None:
        with self._lock:
            row = self._posts.get(post_id)
            if row is None or row["status"] == "withdrawn":
                return None
            self._responses.setdefault(post_id, {})[_identity_hash(submission.responder_id)] = submission
            return self._public(row, submission.responder_id)

    def withdraw(self, post_id: str, owner_id: str) -> bool:
        with self._lock:
            row = self._posts.get(post_id)
            if row is None or row["owner_hash"] != _identity_hash(owner_id):
                return False
            row["status"] = "withdrawn"
            return True

    def _public(self, row: dict[str, Any], requester_id: str | None) -> CommunityPost:
        responses = list(self._responses.get(row["id"], {}).values())
        return CommunityPost(
            **{key: row[key] for key in (
                "id", "alias", "area_id", "area_name", "subject", "sound_type",
                "observed_at", "created_at", "audio_url", "duration_ms",
                "candidate_names", "field_observations", "status", "review_status",
            )},
            response_count=len(responses),
            response_summary=dict(Counter(item.choice for item in responses)),
            owned_by_requester=bool(requester_id) and row["owner_hash"] == _identity_hash(requester_id),
        )


class NeonCommunityRepository:
    def __init__(self, database_url: str) -> None:
        from psycopg.rows import dict_row
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(
            conninfo=database_url,
            min_size=1,
            max_size=4,
            kwargs={"row_factory": dict_row},
            check=ConnectionPool.check_connection,
            max_idle=60,
            max_lifetime=600,
        )

    def _connection(self):
        return self._pool.connection()

    def list_posts(self, *, area_id: str | None = None, requester_id: str | None = None) -> list[CommunityPost]:
        with self._connection() as connection, connection.cursor() as cursor:
            if area_id:
                cursor.execute(
                    "SELECT * FROM community_public_posts WHERE area_id = %s ORDER BY created_at DESC LIMIT 100",
                    (area_id,),
                )
            else:
                cursor.execute(
                    "SELECT * FROM community_public_posts ORDER BY created_at DESC LIMIT 100"
                )
            return [self._map_post(row, requester_id) for row in cursor.fetchall()]

    def get_post(self, post_id: str, *, requester_id: str | None = None) -> CommunityPost | None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT * FROM community_public_posts WHERE id = %s", (post_id,))
            row = cursor.fetchone()
            return self._map_post(row, requester_id) if row else None

    def area_summaries(self) -> list[AreaSummary]:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT * FROM community_area_summaries")
            existing = {row["area_id"]: row for row in cursor.fetchall()}
        return [
            AreaSummary(
                area_id=area_id,
                area_name=name,
                post_count=int(existing.get(area_id, {}).get("post_count", 0)),
                waiting_count=int(existing.get(area_id, {}).get("waiting_count", 0)),
                sound_types=list(existing.get(area_id, {}).get("sound_types") or []),
            )
            for area_id, name in AREA_NAMES.items()
        ]

    def create_post(self, metadata: PublicationMetadata, audio_url: str) -> CommunityPost:
        if not metadata.adult_confirmed or not metadata.public_consent:
            raise PermissionError("公开发布需要成年人确认和独立公开授权")
        post_id = uuid4().hex
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO community_posts
                   (id, owner_hash, alias, area_id, area_name, subject, sound_type,
                    observed_at, audio_url, duration_ms, candidate_names,
                    field_observations, model_snapshot, status, review_status)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s,%s)""",
                (
                    post_id, _identity_hash(metadata.owner_id), metadata.alias,
                    metadata.area_id, metadata.area_name, metadata.subject,
                    metadata.sound_type, metadata.observed_at, audio_url,
                    metadata.duration_ms, json.dumps(metadata.candidate_names, ensure_ascii=False),
                    json.dumps(metadata.field_observations, ensure_ascii=False),
                    json.dumps(metadata.model_snapshot, ensure_ascii=False),
                    "published_unverified", "queued" if metadata.review_consent else "not_requested",
                ),
            )
            cursor.execute(
                "INSERT INTO community_consents (post_id, adult_confirmed, public_consent, review_consent) VALUES (%s,%s,%s,%s)",
                (post_id, metadata.adult_confirmed, metadata.public_consent, metadata.review_consent),
            )
        post = self.get_post(post_id, requester_id=metadata.owner_id)
        if post is None:
            raise RuntimeError("发布成功后无法读取记录")
        return post

    def add_response(self, post_id: str, submission: AssistSubmission) -> CommunityPost | None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT 1 FROM community_posts WHERE id=%s AND status <> 'withdrawn'", (post_id,))
            if cursor.fetchone() is None:
                return None
            cursor.execute(
                """INSERT INTO community_responses
                   (id, post_id, responder_hash, choice, also_heard, key_second)
                   VALUES (%s,%s,%s,%s,%s,%s)
                   ON CONFLICT (post_id, responder_hash) DO UPDATE SET
                     choice=EXCLUDED.choice, also_heard=EXCLUDED.also_heard,
                     key_second=EXCLUDED.key_second, updated_at=now()""",
                (uuid4().hex, post_id, _identity_hash(submission.responder_id), submission.choice,
                 submission.also_heard, submission.key_second),
            )
        return self.get_post(post_id, requester_id=submission.responder_id)

    def withdraw(self, post_id: str, owner_id: str) -> bool:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "UPDATE community_posts SET status='withdrawn', withdrawn_at=now() WHERE id=%s AND owner_hash=%s",
                (post_id, _identity_hash(owner_id)),
            )
            return cursor.rowcount == 1

    def _map_post(self, row: dict[str, Any], requester_id: str | None) -> CommunityPost:
        return CommunityPost(
            id=row["id"], alias=row["alias"], area_id=row["area_id"], area_name=row["area_name"],
            subject=row["subject"], sound_type=row["sound_type"], observed_at=row["observed_at"],
            created_at=row["created_at"], audio_url=row["audio_url"], duration_ms=row["duration_ms"],
            candidate_names=list(row["candidate_names"] or []),
            field_observations=list(row["field_observations"] or []), status=row["status"],
            review_status=row["review_status"], response_count=int(row["response_count"] or 0),
            response_summary=dict(row["response_summary"] or {}),
            owned_by_requester=bool(requester_id) and row["owner_hash"] == _identity_hash(requester_id),
        )


def repository_from_environment() -> CommunityRepository:
    from dotenv import load_dotenv

    load_dotenv(__import__("pathlib").Path(__file__).resolve().parents[2] / ".env")
    database_url = _database_url_from_environment()
    return NeonCommunityRepository(database_url) if database_url else MemoryCommunityRepository()
