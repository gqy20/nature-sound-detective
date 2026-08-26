from __future__ import annotations

import hashlib
import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from threading import RLock
from typing import Any, Protocol
from uuid import uuid4

from app.family_sessions.models import (
    FamilyCommand,
    FamilyExplorationEvent,
    FamilyExplorationEventInput,
    FamilySessionView,
)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _pair_hash(session_id: str, pair_code: str) -> str:
    return hashlib.sha256(f"{session_id}:{pair_code}".encode("utf-8")).hexdigest()


def _pair_lookup_hash(pair_code: str) -> str:
    return hashlib.sha256(pair_code.encode("utf-8")).hexdigest()


class FamilySessionRepository(Protocol):
    def create_session(self, parent_id: str) -> tuple[FamilySessionView, str, datetime]: ...
    def join_session(self, pair_code: str, child_id: str) -> FamilySessionView: ...
    def approve_session(self, session_id: str, parent_id: str) -> FamilySessionView: ...
    def get_session(self, session_id: str, identity: str) -> FamilySessionView: ...
    def append_events(
        self,
        session_id: str,
        child_id: str,
        events: list[FamilyExplorationEventInput],
    ) -> tuple[int, int]: ...
    def list_events(
        self,
        session_id: str,
        parent_id: str,
        after_sequence: int,
    ) -> list[FamilyExplorationEvent]: ...
    def create_command(
        self,
        session_id: str,
        parent_id: str,
        template_id: str,
    ) -> FamilyCommand: ...
    def list_commands(
        self,
        session_id: str,
        child_id: str,
        after_sequence: int,
    ) -> list[FamilyCommand]: ...
    def end_session(self, session_id: str, parent_id: str) -> None: ...


class MemoryFamilySessionRepository:
    def __init__(self) -> None:
        self._sessions: dict[str, dict[str, Any]] = {}
        self._events: dict[str, dict[str, dict[str, Any]]] = {}
        self._commands: dict[str, list[dict[str, Any]]] = {}
        self._lock = RLock()

    def _expire(self, row: dict[str, Any]) -> None:
        if row["status"] not in {"ended", "expired"} and row["expires_at"] <= _now():
            row["status"] = "expired"

    def _view(self, row: dict[str, Any], identity: str) -> FamilySessionView:
        self._expire(row)
        if identity == row["parent_id"]:
            role = "parent"
        elif identity == row.get("child_id"):
            role = "child"
        else:
            raise PermissionError("设备不属于这个家庭探索会话")
        last_sequence = max(
            (event["sequence"] for event in self._events.get(row["id"], {}).values()),
            default=0,
        )
        return FamilySessionView(
            session_id=row["id"],
            role=role,
            status=row["status"],
            child_joined=row.get("child_id") is not None,
            last_event_sequence=last_sequence,
            expires_at=row["expires_at"],
        )

    def create_session(self, parent_id: str) -> tuple[FamilySessionView, str, datetime]:
        with self._lock:
            session_id = uuid4().hex
            now = _now()
            live_pair_hashes = {
                row["pair_code_lookup_hash"]
                for row in self._sessions.values()
                if row["status"] == "waiting_for_child" and row["pair_expires_at"] > now
            }
            pair_code = next(
                (
                    candidate
                    for _ in range(20)
                    if (
                        candidate := f"{secrets.randbelow(1_000_000):06d}"
                    )
                    and _pair_lookup_hash(candidate) not in live_pair_hashes
                ),
                None,
            )
            if pair_code is None:
                raise RuntimeError("暂时无法生成连接码")
            pair_expires_at = now + timedelta(minutes=5)
            row = {
                "id": session_id,
                "parent_id": parent_id,
                "child_id": None,
                "status": "waiting_for_child",
                "pair_code_hash": _pair_hash(session_id, pair_code),
                "pair_code_lookup_hash": _pair_lookup_hash(pair_code),
                "pair_expires_at": pair_expires_at,
                "expires_at": now + timedelta(hours=2),
            }
            self._sessions[session_id] = row
            self._events[session_id] = {}
            self._commands[session_id] = []
            return self._view(row, parent_id), pair_code, pair_expires_at

    def join_session(self, pair_code: str, child_id: str) -> FamilySessionView:
        with self._lock:
            now = _now()
            for row in self._sessions.values():
                self._expire(row)
                if (
                    row["status"] == "waiting_for_child"
                    and row["pair_expires_at"] > now
                    and secrets.compare_digest(
                        row["pair_code_hash"],
                        _pair_hash(row["id"], pair_code),
                    )
                ):
                    if child_id == row["parent_id"]:
                        raise ValueError("家长设备不能同时作为儿童探索端")
                    row["child_id"] = child_id
                    row["status"] = "pending_approval"
                    return self._view(row, child_id)
            raise KeyError("连接码无效或已过期")

    def approve_session(self, session_id: str, parent_id: str) -> FamilySessionView:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row["parent_id"] != parent_id:
                raise PermissionError("只有家长设备可以确认连接")
            self._expire(row)
            if row["status"] != "pending_approval":
                raise ValueError("当前没有等待确认的儿童设备")
            row["status"] = "active"
            return self._view(row, parent_id)

    def get_session(self, session_id: str, identity: str) -> FamilySessionView:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            return self._view(row, identity)

    def append_events(
        self,
        session_id: str,
        child_id: str,
        events: list[FamilyExplorationEventInput],
    ) -> tuple[int, int]:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row.get("child_id") != child_id:
                raise PermissionError("只有已连接的儿童设备可以写入探索事件")
            self._expire(row)
            if row["status"] != "active":
                raise ValueError("家庭探索会话尚未开始或已经结束")
            values = self._events[session_id]
            existing_sequences = {value["sequence"] for value in values.values()}
            accepted = 0
            for event in sorted(events, key=lambda value: value.sequence):
                if event.event_id in values:
                    continue
                if event.sequence in existing_sequences:
                    raise ValueError("探索事件序号冲突")
                values[event.event_id] = {
                    **event.model_dump(mode="python"),
                    "received_at": _now(),
                }
                existing_sequences.add(event.sequence)
                accepted += 1
            return accepted, max(existing_sequences, default=0)

    def list_events(
        self,
        session_id: str,
        parent_id: str,
        after_sequence: int,
    ) -> list[FamilyExplorationEvent]:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row["parent_id"] != parent_id:
                raise PermissionError("只有家长设备可以读取探索事件")
            return [
                FamilyExplorationEvent.model_validate(value)
                for value in sorted(
                    self._events[session_id].values(),
                    key=lambda item: item["sequence"],
                )
                if value["sequence"] > after_sequence
            ]

    def create_command(
        self,
        session_id: str,
        parent_id: str,
        template_id: str,
    ) -> FamilyCommand:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row["parent_id"] != parent_id:
                raise PermissionError("只有家长设备可以发送共同任务")
            self._expire(row)
            if row["status"] != "active":
                raise ValueError("家庭探索会话未连接")
            sequence = len(self._commands[session_id]) + 1
            value = {
                "command_id": f"cmd_{uuid4().hex}",
                "template_id": template_id,
                "sequence": sequence,
                "created_at": _now(),
            }
            self._commands[session_id].append(value)
            return FamilyCommand.model_validate(value)

    def list_commands(
        self,
        session_id: str,
        child_id: str,
        after_sequence: int,
    ) -> list[FamilyCommand]:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row.get("child_id") != child_id:
                raise PermissionError("只有儿童探索端可以读取共同任务")
            return [
                FamilyCommand.model_validate(value)
                for value in self._commands[session_id]
                if value["sequence"] > after_sequence
            ]

    def end_session(self, session_id: str, parent_id: str) -> None:
        with self._lock:
            row = self._sessions.get(session_id)
            if row is None:
                raise KeyError(session_id)
            if row["parent_id"] != parent_id:
                raise PermissionError("只有家长设备可以结束会话")
            row["status"] = "ended"


class NeonFamilySessionRepository:
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

    @staticmethod
    def _view(row: dict[str, Any], identity: str) -> FamilySessionView:
        if identity == row["parent_hash"]:
            role = "parent"
        elif identity == row.get("child_hash"):
            role = "child"
        else:
            raise PermissionError("设备不属于这个家庭探索会话")
        return FamilySessionView(
            session_id=row["id"],
            role=role,
            status=row["status"],
            child_joined=row.get("child_hash") is not None,
            last_event_sequence=int(row.get("last_event_sequence") or 0),
            expires_at=row["expires_at"],
        )

    def _session_row(self, cursor, session_id: str) -> dict[str, Any]:
        cursor.execute(
            """SELECT s.*,
                      COALESCE((SELECT max(sequence) FROM family_exploration_events e
                                WHERE e.session_id=s.id), 0) AS last_event_sequence
                 FROM family_exploration_sessions s WHERE s.id=%s""",
            (session_id,),
        )
        row = cursor.fetchone()
        if row is None:
            raise KeyError(session_id)
        return row

    def create_session(self, parent_id: str) -> tuple[FamilySessionView, str, datetime]:
        session_id = uuid4().hex
        now = _now()
        pair_expires_at = now + timedelta(minutes=5)
        expires_at = now + timedelta(hours=2)
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_xact_lock(hashtext('family_pair_code'))")
            pair_code = None
            for _ in range(20):
                candidate = f"{secrets.randbelow(1_000_000):06d}"
                cursor.execute(
                    """SELECT 1 FROM family_exploration_sessions
                       WHERE pair_code_lookup_hash=%s
                         AND status='waiting_for_child' AND pair_expires_at>now()
                       LIMIT 1""",
                    (_pair_lookup_hash(candidate),),
                )
                if cursor.fetchone() is None:
                    pair_code = candidate
                    break
            if pair_code is None:
                raise RuntimeError("暂时无法生成连接码")
            cursor.execute(
                """INSERT INTO family_exploration_sessions
                   (id,parent_hash,status,pair_code_hash,pair_code_lookup_hash,
                    pair_expires_at,expires_at)
                   VALUES (%s,%s,'waiting_for_child',%s,%s,%s,%s)""",
                (
                    session_id,
                    parent_id,
                    _pair_hash(session_id, pair_code),
                    _pair_lookup_hash(pair_code),
                    pair_expires_at,
                    expires_at,
                ),
            )
            row = self._session_row(cursor, session_id)
        return self._view(row, parent_id), pair_code, pair_expires_at

    def join_session(self, pair_code: str, child_id: str) -> FamilySessionView:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                """SELECT * FROM family_exploration_sessions
                   WHERE status='waiting_for_child' AND pair_expires_at>now()
                     AND expires_at>now() AND pair_code_lookup_hash=%s
                   ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
                (_pair_lookup_hash(pair_code),),
            )
            row = cursor.fetchone()
            if row is not None and not secrets.compare_digest(
                row["pair_code_hash"],
                _pair_hash(row["id"], pair_code),
            ):
                row = None
            if row is None:
                raise KeyError("连接码无效或已过期")
            if row["parent_hash"] == child_id:
                raise ValueError("家长设备不能同时作为儿童探索端")
            cursor.execute(
                """UPDATE family_exploration_sessions
                   SET child_hash=%s,status='pending_approval',child_joined_at=now()
                   WHERE id=%s""",
                (child_id, row["id"]),
            )
            updated = self._session_row(cursor, row["id"])
        return self._view(updated, child_id)

    def approve_session(self, session_id: str, parent_id: str) -> FamilySessionView:
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row["parent_hash"] != parent_id:
                raise PermissionError("只有家长设备可以确认连接")
            if row["expires_at"] <= _now():
                cursor.execute(
                    "UPDATE family_exploration_sessions SET status='expired' WHERE id=%s",
                    (session_id,),
                )
                raise ValueError("家庭探索会话已过期")
            if row["status"] != "pending_approval":
                raise ValueError("当前没有等待确认的儿童设备")
            cursor.execute(
                """UPDATE family_exploration_sessions
                   SET status='active',approved_at=now() WHERE id=%s""",
                (session_id,),
            )
            updated = self._session_row(cursor, session_id)
        return self._view(updated, parent_id)

    def get_session(self, session_id: str, identity: str) -> FamilySessionView:
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row["expires_at"] <= _now() and row["status"] not in {"ended", "expired"}:
                cursor.execute(
                    "UPDATE family_exploration_sessions SET status='expired' WHERE id=%s",
                    (session_id,),
                )
                row["status"] = "expired"
        return self._view(row, identity)

    def append_events(
        self,
        session_id: str,
        child_id: str,
        events: list[FamilyExplorationEventInput],
    ) -> tuple[int, int]:
        accepted = 0
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row.get("child_hash") != child_id:
                raise PermissionError("只有已连接的儿童设备可以写入探索事件")
            if row["status"] != "active" or row["expires_at"] <= _now():
                raise ValueError("家庭探索会话尚未开始或已经结束")
            for event in sorted(events, key=lambda value: value.sequence):
                cursor.execute(
                    """INSERT INTO family_exploration_events
                       (event_id,session_id,sequence,event_type,payload,occurred_at)
                       VALUES (%s,%s,%s,%s,%s::jsonb,%s)
                       ON CONFLICT DO NOTHING""",
                    (
                        event.event_id,
                        session_id,
                        event.sequence,
                        event.event_type,
                        json.dumps(event.payload, ensure_ascii=False),
                        event.occurred_at,
                    ),
                )
                accepted += cursor.rowcount
            cursor.execute(
                "SELECT COALESCE(max(sequence),0) AS value FROM family_exploration_events WHERE session_id=%s",
                (session_id,),
            )
            last_sequence = int(cursor.fetchone()["value"])
        return accepted, last_sequence

    def list_events(
        self,
        session_id: str,
        parent_id: str,
        after_sequence: int,
    ) -> list[FamilyExplorationEvent]:
        with self._connection() as connection, connection.cursor() as cursor:
            cursor.execute(
                "SELECT id FROM family_exploration_sessions WHERE id=%s FOR UPDATE",
                (session_id,),
            )
            row = self._session_row(cursor, session_id)
            if row["parent_hash"] != parent_id:
                raise PermissionError("只有家长设备可以读取探索事件")
            cursor.execute(
                """SELECT event_id,sequence,event_type,payload,occurred_at,received_at
                   FROM family_exploration_events
                   WHERE session_id=%s AND sequence>%s ORDER BY sequence LIMIT 100""",
                (session_id, after_sequence),
            )
            return [FamilyExplorationEvent.model_validate(value) for value in cursor.fetchall()]

    def create_command(
        self,
        session_id: str,
        parent_id: str,
        template_id: str,
    ) -> FamilyCommand:
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row["parent_hash"] != parent_id:
                raise PermissionError("只有家长设备可以发送共同任务")
            if row["status"] != "active" or row["expires_at"] <= _now():
                raise ValueError("家庭探索会话未连接")
            cursor.execute(
                "SELECT COALESCE(max(sequence),0)+1 AS value FROM family_session_commands WHERE session_id=%s",
                (session_id,),
            )
            sequence = int(cursor.fetchone()["value"])
            value = {
                "command_id": f"cmd_{uuid4().hex}",
                "template_id": template_id,
                "sequence": sequence,
                "created_at": _now(),
            }
            cursor.execute(
                """INSERT INTO family_session_commands
                   (command_id,session_id,sequence,template_id,created_at)
                   VALUES (%s,%s,%s,%s,%s)""",
                (
                    value["command_id"],
                    session_id,
                    sequence,
                    template_id,
                    value["created_at"],
                ),
            )
        return FamilyCommand.model_validate(value)

    def list_commands(
        self,
        session_id: str,
        child_id: str,
        after_sequence: int,
    ) -> list[FamilyCommand]:
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row.get("child_hash") != child_id:
                raise PermissionError("只有儿童探索端可以读取共同任务")
            cursor.execute(
                """SELECT command_id,template_id,sequence,created_at
                   FROM family_session_commands
                   WHERE session_id=%s AND sequence>%s ORDER BY sequence LIMIT 50""",
                (session_id, after_sequence),
            )
            return [FamilyCommand.model_validate(value) for value in cursor.fetchall()]

    def end_session(self, session_id: str, parent_id: str) -> None:
        with self._connection() as connection, connection.cursor() as cursor:
            row = self._session_row(cursor, session_id)
            if row["parent_hash"] != parent_id:
                raise PermissionError("只有家长设备可以结束会话")
            cursor.execute(
                """UPDATE family_exploration_sessions
                   SET status='ended',ended_at=now() WHERE id=%s""",
                (session_id,),
            )


def family_repository_from_environment() -> FamilySessionRepository:
    database_url = os.getenv("DATABASE_URL", "").strip().lstrip("\ufeff").strip()
    return (
        NeonFamilySessionRepository(database_url)
        if database_url
        else MemoryFamilySessionRepository()
    )
