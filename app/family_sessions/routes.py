from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException, Query

from app.community.auth import CommunityAuth, InMemoryRateLimiter, InvalidCommunityToken
from app.family_sessions.models import (
    FamilyCommand,
    FamilyCommandCreate,
    FamilyEventBatchResult,
    FamilyExplorationEvent,
    FamilyExplorationEventBatch,
    FamilySessionCreateResponse,
    FamilySessionJoinRequest,
    FamilySessionView,
)
from app.family_sessions.repository import (
    FamilySessionRepository,
    family_repository_from_environment,
)


def build_family_session_router(
    repository: FamilySessionRepository | None = None,
    *,
    auth: CommunityAuth | None = None,
    rate_limiter: InMemoryRateLimiter | None = None,
) -> APIRouter:
    repo = repository or family_repository_from_environment()
    session_auth = auth or CommunityAuth.from_environment()
    limiter = rate_limiter or InMemoryRateLimiter()
    router = APIRouter(prefix="/api/family-sessions", tags=["family-sessions"])

    def identity_from(authorization: str | None) -> str:
        try:
            return session_auth.verify(authorization)
        except InvalidCommunityToken as exc:
            raise HTTPException(
                401,
                str(exc),
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc

    def enforce(identity: str, scope: str, *, limit: int) -> None:
        if not limiter.allow(
            f"family:{scope}:{identity}",
            limit=limit,
            window_seconds=3600,
        ):
            raise HTTPException(429, "操作太频繁，请稍后再试")

    def translate(error: Exception) -> HTTPException:
        if isinstance(error, KeyError):
            return HTTPException(404, str(error.args[0]))
        if isinstance(error, PermissionError):
            return HTTPException(403, str(error))
        if isinstance(error, ValueError):
            return HTTPException(409, str(error))
        return HTTPException(500, "家庭探索会话暂时不可用")

    @router.post("", response_model=FamilySessionCreateResponse, status_code=201)
    def create_session(
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce(identity, "create", limit=20)
        try:
            view, pair_code, pair_expires_at = repo.create_session(identity)
            return FamilySessionCreateResponse(
                session_id=view.session_id,
                pair_code=pair_code,
                status=view.status,
                pair_expires_at=pair_expires_at,
                expires_at=view.expires_at,
            )
        except Exception as error:
            raise translate(error) from error

    @router.post("/join", response_model=FamilySessionView)
    def join_session(
        payload: FamilySessionJoinRequest,
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce(identity, "join", limit=30)
        try:
            return repo.join_session(payload.pair_code, identity)
        except Exception as error:
            raise translate(error) from error

    @router.get("/{session_id}", response_model=FamilySessionView)
    def get_session(
        session_id: str,
        authorization: str | None = Header(default=None),
    ):
        try:
            return repo.get_session(session_id, identity_from(authorization))
        except Exception as error:
            raise translate(error) from error

    @router.post("/{session_id}/approve", response_model=FamilySessionView)
    def approve_session(
        session_id: str,
        authorization: str | None = Header(default=None),
    ):
        try:
            return repo.approve_session(session_id, identity_from(authorization))
        except Exception as error:
            raise translate(error) from error

    @router.post(
        "/{session_id}/events/batch",
        response_model=FamilyEventBatchResult,
    )
    def append_events(
        session_id: str,
        payload: FamilyExplorationEventBatch,
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce(identity, "events", limit=600)
        try:
            accepted, last_sequence = repo.append_events(
                session_id,
                identity,
                payload.events,
            )
            return FamilyEventBatchResult(
                accepted=accepted,
                last_sequence=last_sequence,
            )
        except Exception as error:
            raise translate(error) from error

    @router.get(
        "/{session_id}/events",
        response_model=list[FamilyExplorationEvent],
    )
    def list_events(
        session_id: str,
        after_sequence: int = Query(default=0, ge=0),
        authorization: str | None = Header(default=None),
    ):
        try:
            return repo.list_events(
                session_id,
                identity_from(authorization),
                after_sequence,
            )
        except Exception as error:
            raise translate(error) from error

    @router.post(
        "/{session_id}/commands",
        response_model=FamilyCommand,
        status_code=201,
    )
    def create_command(
        session_id: str,
        payload: FamilyCommandCreate,
        authorization: str | None = Header(default=None),
    ):
        try:
            return repo.create_command(
                session_id,
                identity_from(authorization),
                payload.template_id,
            )
        except Exception as error:
            raise translate(error) from error

    @router.get("/{session_id}/commands", response_model=list[FamilyCommand])
    def list_commands(
        session_id: str,
        after_sequence: int = Query(default=0, ge=0),
        authorization: str | None = Header(default=None),
    ):
        try:
            return repo.list_commands(
                session_id,
                identity_from(authorization),
                after_sequence,
            )
        except Exception as error:
            raise translate(error) from error

    @router.post("/{session_id}/end", status_code=204)
    def end_session(
        session_id: str,
        authorization: str | None = Header(default=None),
    ) -> None:
        try:
            repo.end_session(session_id, identity_from(authorization))
        except Exception as error:
            raise translate(error) from error

    return router
