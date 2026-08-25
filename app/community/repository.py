from __future__ import annotations

import hashlib
import json
import os
from collections import Counter
from datetime import timedelta
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
    EcologySnapshot,
    ParkSite,
    ParkSummary,
    CommunityMediaAsset,
    ZoneSoundscapeSummary,
)
from app.community.catalog import PILOT_PARKS, park_by_id


def _identity_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _database_url_from_environment() -> str:
    """Normalize secrets copied from files or deployment dashboards.

    A UTF-8 BOM can survive PowerShell pipelines and is not removed by
    ``str.strip()``. Psycopg then interprets the entire URL as an option name.
    """
    return os.getenv("DATABASE_URL", "").strip().lstrip("\ufeff").strip()


def _data_sufficiency(post_count: int, observer_count: int) -> str:
    if post_count >= 20 and observer_count >= 8:
        return "high"
    if post_count >= 6 and observer_count >= 3:
        return "medium"
    return "low"


def _build_ecology_snapshot(
    park_id: str,
    period_days: int,
    rows: list[dict[str, Any]],
    *,
    now,
) -> EcologySnapshot:
    park = park_by_id(park_id)
    if park is None:
        raise KeyError(park_id)
    current_cutoff = now - timedelta(days=period_days)
    previous_cutoff = now - timedelta(days=period_days * 2)
    current = [row for row in rows if row["observed_at"] >= current_cutoff]
    previous = [
        row
        for row in rows
        if previous_cutoff <= row["observed_at"] < current_cutoff
    ]
    observers = {row["owner_hash"] for row in current}
    current_count = len(current)
    previous_count = len(previous)
    if current_count < 6 or previous_count < 6:
        activity_trend = "insufficient"
    elif current_count > previous_count * 1.25:
        activity_trend = "higher"
    elif current_count < previous_count * 0.75:
        activity_trend = "lower"
    else:
        activity_trend = "similar"
    zone_summaries = []
    for zone in park["zones"]:
        zone_rows = [row for row in current if row.get("zone_id") == zone["id"]]
        zone_observers = {row["owner_hash"] for row in zone_rows}
        zone_summaries.append(
            ZoneSoundscapeSummary(
                zone_id=zone["id"],
                zone_name=zone["name"],
                valid_post_count=len(zone_rows),
                independent_observer_count=len(zone_observers),
                sound_type_counts=dict(
                    Counter(row["sound_type"] for row in zone_rows)
                ),
                data_sufficiency=_data_sufficiency(
                    len(zone_rows), len(zone_observers)
                ),
            )
        )
    return EcologySnapshot(
        park_id=park_id,
        period_days=period_days,
        valid_post_count=current_count,
        independent_observer_count=len(observers),
        sound_type_counts=dict(Counter(row["sound_type"] for row in current)),
        reviewed_post_count=sum(
            row["review_status"] == "confirmed" for row in current
        ),
        data_sufficiency=_data_sufficiency(current_count, len(observers)),
        observation_day_count=len({row["observed_at"].date() for row in current}),
        sampling_mode_counts=dict(
            Counter(row.get("sampling_mode", "opportunistic") for row in current)
        ),
        previous_valid_post_count=previous_count,
        activity_trend=activity_trend,
        zone_summaries=zone_summaries,
    )


class CommunityRepository(Protocol):
    def list_posts(self, *, area_id: str | None, requester_id: str | None) -> list[CommunityPost]: ...
    def get_post(self, post_id: str, *, requester_id: str | None) -> CommunityPost | None: ...
    def area_summaries(self) -> list[AreaSummary]: ...
    def create_post(self, metadata: PublicationMetadata, audio_url: str) -> CommunityPost: ...
    def add_response(self, post_id: str, submission: AssistSubmission) -> CommunityPost | None: ...
    def withdraw(self, post_id: str, owner_id: str) -> bool: ...
    def park_summaries(self) -> list[ParkSummary]: ...
    def park_sites(self, park_id: str | None = None) -> list[ParkSite]: ...
    def ecology_snapshot(self, park_id: str, period_days: int = 7) -> EcologySnapshot: ...
    def add_media_asset(self, post_id: str, owner_id: str, asset: CommunityMediaAsset) -> bool: ...
    def reserve_parent_guidance(self, identity: str, limit: int) -> tuple[bool, int]: ...
    def refund_parent_guidance(self, identity: str) -> int: ...
    def parent_guidance_usage(self, identity: str) -> int: ...
    def get_parent_guidance_cache(self, identity: str, fingerprint: str) -> dict[str, Any] | None: ...
    def claim_parent_guidance_cache(self, identity: str, fingerprint: str) -> bool: ...
    def complete_parent_guidance_cache(self, identity: str, fingerprint: str, payload: dict[str, Any]) -> None: ...
    def release_parent_guidance_cache(self, identity: str, fingerprint: str) -> None: ...


class MemoryCommunityRepository:
    """Deterministic fallback for tests and offline competition rehearsals."""

    def __init__(self) -> None:
        self._posts: dict[str, dict[str, Any]] = {}
        self._responses: dict[str, dict[str, AssistSubmission]] = {}
        self._media: dict[str, list[CommunityMediaAsset]] = {}
        self._parent_guidance_usage: dict[str, int] = {}
        self._parent_guidance_cache: dict[tuple[str, str], dict[str, Any] | None] = {}
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
            "model_snapshot": dict(metadata.model_snapshot),
            "status": "published_unverified",
            "review_status": "queued" if metadata.review_consent else "not_requested",
            "park_id": metadata.park_id,
            "zone_id": metadata.zone_id,
            "site_id": metadata.site_id,
            "sampling_mode": metadata.sampling_mode,
            "sampling_effort": dict(metadata.sampling_effort),
            "audio_quality": dict(metadata.audio_quality),
            "ecology_eligible": metadata.ecology_eligible,
        }
        with self._lock:
            self._posts[post_id] = row
            self._responses[post_id] = {}
            self._media[post_id] = []
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
            park_id=row.get("park_id"), zone_id=row.get("zone_id"), site_id=row.get("site_id"),
            sampling_mode=row.get("sampling_mode", "opportunistic"),
            sampling_effort=dict(row.get("sampling_effort") or {}),
            audio_quality=dict(row.get("audio_quality") or {}),
            ecology_eligible=bool(row.get("ecology_eligible", True)),
            is_demo=bool((row.get("model_snapshot") or {}).get("demo", False)),
            media_assets=list(self._media.get(row["id"], [])),
        )

    def add_media_asset(self, post_id: str, owner_id: str, asset: CommunityMediaAsset) -> bool:
        with self._lock:
            row = self._posts.get(post_id)
            if row is None or row["owner_hash"] != _identity_hash(owner_id) or row["status"] == "withdrawn":
                return False
            self._media.setdefault(post_id, []).append(asset)
            return True

    def reserve_parent_guidance(self, identity: str, limit: int) -> tuple[bool, int]:
        with self._lock:
            used = self._parent_guidance_usage.get(identity, 0)
            if used >= limit:
                return False, used
            used += 1
            self._parent_guidance_usage[identity] = used
            return True, used

    def refund_parent_guidance(self, identity: str) -> int:
        with self._lock:
            used = max(0, self._parent_guidance_usage.get(identity, 0) - 1)
            self._parent_guidance_usage[identity] = used
            return used

    def parent_guidance_usage(self, identity: str) -> int:
        with self._lock:
            return self._parent_guidance_usage.get(identity, 0)

    def get_parent_guidance_cache(
        self, identity: str, fingerprint: str
    ) -> dict[str, Any] | None:
        with self._lock:
            value = self._parent_guidance_cache.get((identity, fingerprint))
            return json.loads(json.dumps(value)) if value is not None else None

    def claim_parent_guidance_cache(self, identity: str, fingerprint: str) -> bool:
        with self._lock:
            key = (identity, fingerprint)
            if key in self._parent_guidance_cache:
                return False
            self._parent_guidance_cache[key] = None
            return True

    def complete_parent_guidance_cache(
        self,
        identity: str,
        fingerprint: str,
        payload: dict[str, Any],
    ) -> None:
        with self._lock:
            self._parent_guidance_cache[(identity, fingerprint)] = json.loads(
                json.dumps(payload)
            )

    def release_parent_guidance_cache(self, identity: str, fingerprint: str) -> None:
        with self._lock:
            key = (identity, fingerprint)
            if self._parent_guidance_cache.get(key) is None:
                self._parent_guidance_cache.pop(key, None)

    def park_summaries(self) -> list[ParkSummary]:
        return [
            ParkSummary(
                park_id=park["id"], park_name=park["name"], area_id=park["area_id"],
                area_name=park["area_name"], public_centroid=park["public_centroid"],
                habitat_tags=park["habitat_tags"], zone_count=len(park["zones"]),
            )
            for park in PILOT_PARKS
        ]

    def park_sites(self, park_id: str | None = None) -> list[ParkSite]:
        parks = [park for park in PILOT_PARKS if park_id is None or park["id"] == park_id]
        return [
            ParkSite(
                id=f"{park['id']}:{zone['id']}", park_id=park["id"], park_name=park["name"],
                zone_id=zone["id"], zone_name=zone["name"], area_id=park["area_id"],
                area_name=park["area_name"], public_centroid=park["public_centroid"],
                habitat_tags=zone["habitat_tags"],
            )
            for park in parks for zone in park["zones"]
        ]

    def ecology_snapshot(self, park_id: str, period_days: int = 7) -> EcologySnapshot:
        if park_by_id(park_id) is None:
            raise KeyError(park_id)
        now = utc_now()
        cutoff = now - timedelta(days=period_days * 2)
        with self._lock:
            rows = [
                row for row in self._posts.values()
                if row.get("park_id") == park_id
                and row["status"] != "withdrawn"
                and row.get("ecology_eligible", True)
                and row["observed_at"] >= cutoff
            ]
        return _build_ecology_snapshot(
            park_id,
            period_days,
            rows,
            now=now,
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
            rows = list(cursor.fetchall())
        media_by_post = self._media_assets_by_post_ids(
            [row["id"] for row in rows]
        )
        return [
            self._map_post(
                row,
                requester_id,
                media_assets=media_by_post.get(row["id"], []),
            )
            for row in rows
        ]

    def get_post(self, post_id: str, *, requester_id: str | None = None) -> CommunityPost | None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT * FROM community_public_posts WHERE id = %s", (post_id,))
            row = cursor.fetchone()
        if row is None:
            return None
        media = self._media_assets_by_post_ids([post_id]).get(post_id, [])
        return self._map_post(row, requester_id, media_assets=media)

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
                    field_observations, model_snapshot, status, review_status,
                    park_id, zone_id, site_id, sampling_mode, sampling_effort,
                    audio_quality, ecology_eligible)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s)""",
                (
                    post_id, _identity_hash(metadata.owner_id), metadata.alias,
                    metadata.area_id, metadata.area_name, metadata.subject,
                    metadata.sound_type, metadata.observed_at, audio_url,
                    metadata.duration_ms, json.dumps(metadata.candidate_names, ensure_ascii=False),
                    json.dumps(metadata.field_observations, ensure_ascii=False),
                    json.dumps(metadata.model_snapshot, ensure_ascii=False),
                    "published_unverified", "queued" if metadata.review_consent else "not_requested",
                    metadata.park_id, metadata.zone_id, metadata.site_id, metadata.sampling_mode,
                    json.dumps(metadata.sampling_effort, ensure_ascii=False),
                    json.dumps(metadata.audio_quality, ensure_ascii=False), metadata.ecology_eligible,
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

    def _media_assets_by_post_ids(
        self, post_ids: list[str]
    ) -> dict[str, list[CommunityMediaAsset]]:
        grouped = {post_id: [] for post_id in post_ids}
        if not post_ids:
            return grouped
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """SELECT * FROM community_media_assets
                   WHERE post_id = ANY(%s) AND moderation_status='approved'
                   ORDER BY post_id, created_at""",
                (post_ids,),
            )
            for item in cursor.fetchall():
                grouped.setdefault(item["post_id"], []).append(
                    CommunityMediaAsset(
                        id=item["id"],
                        media_type=item["media_type"],
                        source_type=item["source_type"],
                        url=item["storage_url"],
                        thumbnail_url=item.get("thumbnail_url"),
                        provider=item.get("provider"),
                        model=item.get("model"),
                        moderation_status=item["moderation_status"],
                    )
                )
        return grouped

    def _map_post(
        self,
        row: dict[str, Any],
        requester_id: str | None,
        *,
        media_assets: list[CommunityMediaAsset],
    ) -> CommunityPost:
        return CommunityPost(
            id=row["id"], alias=row["alias"], area_id=row["area_id"], area_name=row["area_name"],
            subject=row["subject"], sound_type=row["sound_type"], observed_at=row["observed_at"],
            created_at=row["created_at"], audio_url=row["audio_url"], duration_ms=row["duration_ms"],
            candidate_names=list(row["candidate_names"] or []),
            field_observations=list(row["field_observations"] or []), status=row["status"],
            review_status=row["review_status"], response_count=int(row["response_count"] or 0),
            response_summary=dict(row["response_summary"] or {}),
            owned_by_requester=bool(requester_id) and row["owner_hash"] == _identity_hash(requester_id),
            park_id=row.get("park_id"), zone_id=row.get("zone_id"), site_id=row.get("site_id"),
            sampling_mode=row.get("sampling_mode", "opportunistic"),
            sampling_effort=dict(row.get("sampling_effort") or {}),
            audio_quality=dict(row.get("audio_quality") or {}),
            ecology_eligible=bool(row.get("ecology_eligible", True)),
            is_demo=bool((row.get("model_snapshot") or {}).get("demo", False)),
            media_assets=media_assets,
        )

    def add_media_asset(self, post_id: str, owner_id: str, asset: CommunityMediaAsset) -> bool:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "SELECT 1 FROM community_posts WHERE id=%s AND owner_hash=%s AND status<>'withdrawn'",
                (post_id, _identity_hash(owner_id)),
            )
            if cursor.fetchone() is None:
                return False
            cursor.execute(
                """INSERT INTO community_media_assets
                   (id, post_id, media_type, source_type, storage_url, thumbnail_url,
                    provider, model, moderation_status)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (
                    asset.id, post_id, asset.media_type, asset.source_type, asset.url,
                    asset.thumbnail_url, asset.provider, asset.model, asset.moderation_status,
                ),
            )
            return True

    def reserve_parent_guidance(self, identity: str, limit: int) -> tuple[bool, int]:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO community_parent_guidance_quotas
                   (identity_hash, used_count) VALUES (%s, 1)
                   ON CONFLICT (identity_hash) DO UPDATE SET
                     used_count=community_parent_guidance_quotas.used_count + 1,
                     updated_at=now()
                   WHERE community_parent_guidance_quotas.used_count < %s
                   RETURNING used_count""",
                (identity, limit),
            )
            row = cursor.fetchone()
            if row is not None:
                return True, int(row["used_count"])
            cursor.execute(
                "SELECT used_count FROM community_parent_guidance_quotas WHERE identity_hash=%s",
                (identity,),
            )
            existing = cursor.fetchone()
            return False, int(existing["used_count"] if existing else limit)

    def refund_parent_guidance(self, identity: str) -> int:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """UPDATE community_parent_guidance_quotas SET
                     used_count=greatest(used_count - 1, 0), updated_at=now()
                   WHERE identity_hash=%s RETURNING used_count""",
                (identity,),
            )
            row = cursor.fetchone()
            return int(row["used_count"] if row else 0)

    def parent_guidance_usage(self, identity: str) -> int:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "SELECT used_count FROM community_parent_guidance_quotas WHERE identity_hash=%s",
                (identity,),
            )
            row = cursor.fetchone()
            return int(row["used_count"] if row else 0)

    def get_parent_guidance_cache(
        self, identity: str, fingerprint: str
    ) -> dict[str, Any] | None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """SELECT response_payload FROM community_parent_guidance_cache
                   WHERE identity_hash=%s AND request_fingerprint=%s
                     AND status='completed'""",
                (identity, fingerprint),
            )
            row = cursor.fetchone()
            return dict(row["response_payload"]) if row else None

    def claim_parent_guidance_cache(self, identity: str, fingerprint: str) -> bool:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO community_parent_guidance_cache
                   (identity_hash, request_fingerprint, status)
                   VALUES (%s, %s, 'pending')
                   ON CONFLICT (identity_hash, request_fingerprint) DO UPDATE SET
                     status='pending', response_payload=NULL, updated_at=now()
                   WHERE community_parent_guidance_cache.status='pending'
                     AND community_parent_guidance_cache.updated_at < now() - interval '2 minutes'
                   RETURNING request_fingerprint""",
                (identity, fingerprint),
            )
            return cursor.fetchone() is not None

    def complete_parent_guidance_cache(
        self,
        identity: str,
        fingerprint: str,
        payload: dict[str, Any],
    ) -> None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """UPDATE community_parent_guidance_cache SET
                     status='completed', response_payload=%s::jsonb, updated_at=now()
                   WHERE identity_hash=%s AND request_fingerprint=%s""",
                (json.dumps(payload, ensure_ascii=False), identity, fingerprint),
            )

    def release_parent_guidance_cache(self, identity: str, fingerprint: str) -> None:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """DELETE FROM community_parent_guidance_cache
                   WHERE identity_hash=%s AND request_fingerprint=%s
                     AND status='pending'""",
                (identity, fingerprint),
            )

    def park_summaries(self) -> list[ParkSummary]:
        return MemoryCommunityRepository().park_summaries()

    def park_sites(self, park_id: str | None = None) -> list[ParkSite]:
        return MemoryCommunityRepository().park_sites(park_id)

    def ecology_snapshot(self, park_id: str, period_days: int = 7) -> EcologySnapshot:
        if park_by_id(park_id) is None:
            raise KeyError(park_id)
        now = utc_now()
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """SELECT owner_hash, review_status, sound_type, observed_at,
                          sampling_mode, zone_id
                   FROM community_posts
                   WHERE park_id=%s AND ecology_eligible=true AND status<>'withdrawn'
                     AND observed_at >= %s""",
                (park_id, now - timedelta(days=period_days * 2)),
            )
            rows = list(cursor.fetchall())
        return _build_ecology_snapshot(
            park_id,
            period_days,
            rows,
            now=now,
        )


def repository_from_environment() -> CommunityRepository:
    from dotenv import load_dotenv

    load_dotenv(__import__("pathlib").Path(__file__).resolve().parents[2] / ".env")
    database_url = _database_url_from_environment()
    return NeonCommunityRepository(database_url) if database_url else MemoryCommunityRepository()
