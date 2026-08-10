from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

from fastapi import APIRouter, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import ValidationError

from app.community.auth import CommunityAuth, InMemoryRateLimiter, InvalidCommunityToken
from app.community.models import (
    AssistSubmission,
    DeviceSessionRequest,
    DeviceSessionResponse,
    PublicationMetadata,
    PublicationResult,
)
from app.community.repository import CommunityRepository, repository_from_environment
from app.community.storage import (
    CommunityMediaStore,
    CommunityMediaUnavailable,
    media_store_from_environment,
)
from app.config import COMMUNITY_MEDIA_DIR


MAX_COMMUNITY_AUDIO_BYTES = 4 * 1024 * 1024


def build_community_router(
    repository: CommunityRepository | None = None,
    *,
    media_store: CommunityMediaStore | None = None,
    auth: CommunityAuth | None = None,
    rate_limiter: InMemoryRateLimiter | None = None,
) -> APIRouter:
    repo = repository or repository_from_environment()
    store = media_store or media_store_from_environment(COMMUNITY_MEDIA_DIR)
    community_auth = auth or CommunityAuth.from_environment()
    limiter = rate_limiter or InMemoryRateLimiter()
    router = APIRouter(prefix="/api/community", tags=["community"])

    def client_key(request: Request) -> str:
        forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
        if forwarded:
            return forwarded
        return request.client.host if request.client else "unknown"

    def enforce_limit(
        request: Request,
        scope: str,
        identity: str,
        *,
        limit: int,
        window_seconds: int,
    ) -> None:
        if not limiter.allow(
            f"{scope}:{identity}", limit=limit, window_seconds=window_seconds
        ):
            raise HTTPException(429, "操作太频繁，请稍后再试")

    def identity_from(authorization: str | None) -> str:
        try:
            return community_auth.verify(authorization)
        except InvalidCommunityToken as exc:
            raise HTTPException(
                401,
                str(exc),
                headers={"WWW-Authenticate": "Bearer"},
            ) from exc

    def optional_identity(authorization: str | None) -> str | None:
        return identity_from(authorization) if authorization else None

    def anonymous_alias(identity: str) -> str:
        number = int(identity[:8], 16) % 900 + 100
        names = ("雾林探员", "银杏叶探员", "湖畔听者", "晨风探员")
        return f"{names[number % len(names)]} {number}"

    @router.post("/session", response_model=DeviceSessionResponse)
    def create_session(payload: DeviceSessionRequest, request: Request):
        enforce_limit(
            request,
            "session",
            client_key(request),
            limit=20,
            window_seconds=60,
        )
        session = community_auth.issue(payload.device_id)
        return DeviceSessionResponse(
            token=session.token,
            expires_at=session.expires_at,
        )

    @router.get("/areas")
    def areas():
        return [item.model_dump(mode="json") for item in repo.area_summaries()]

    @router.get("/posts")
    def list_posts(
        area_id: str | None = None,
        authorization: str | None = Header(default=None),
    ):
        identity = optional_identity(authorization)
        return [
            item.model_dump(mode="json")
            for item in repo.list_posts(area_id=area_id, requester_id=identity)
        ]

    @router.get("/posts/{post_id}")
    def get_post(
        post_id: str,
        authorization: str | None = Header(default=None),
    ):
        post = repo.get_post(
            post_id,
            requester_id=optional_identity(authorization),
        )
        if post is None:
            raise HTTPException(404, "没有找到这条声音线索")
        return post.model_dump(mode="json")

    @router.post("/posts", status_code=201, response_model=PublicationResult)
    async def create_post(
        request: Request,
        metadata: str = Form(...),
        audio: UploadFile = File(...),
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce_limit(
            request,
            "publish",
            identity,
            limit=8,
            window_seconds=3600,
        )
        try:
            parsed = PublicationMetadata.model_validate_json(metadata)
        except ValidationError as exc:
            raise HTTPException(422, "发布信息不完整或无效") from exc
        suffix = Path(audio.filename or "clip.wav").suffix.lower()
        if suffix not in {".wav", ".mp3", ".m4a", ".ogg", ".aac"}:
            raise HTTPException(415, "公开声音仅支持常见音频格式")
        payload = await audio.read(MAX_COMMUNITY_AUDIO_BYTES + 1)
        if len(payload) > MAX_COMMUNITY_AUDIO_BYTES:
            raise HTTPException(413, "公开声音片段不能超过 4MB")
        if len(payload) < 44:
            raise HTTPException(422, "声音片段无效")
        media_name = f"{uuid4().hex}{suffix}"
        try:
            audio_url = store.save(
                media_name,
                payload,
                audio.content_type or "application/octet-stream",
            )
        except CommunityMediaUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc
        parsed = parsed.model_copy(
            update={"owner_id": identity, "alias": anonymous_alias(identity)}
        )
        try:
            post = repo.create_post(parsed, audio_url)
        except PermissionError as exc:
            store.delete(media_name)
            raise HTTPException(403, str(exc)) from exc
        except Exception:
            store.delete(media_name)
            raise
        return PublicationResult(post=post)

    @router.get("/media/{media_name}")
    def media(media_name: str):
        if not re.fullmatch(r"[a-f0-9]{32}\.(wav|mp3|m4a|ogg|aac)", media_name):
            raise HTTPException(404, "声音片段不存在")
        path = store.local_path(media_name)
        if path is None:
            raise HTTPException(404, "声音片段不存在")
        return FileResponse(path)

    @router.post("/posts/{post_id}/responses")
    def add_response(
        post_id: str,
        submission: AssistSubmission,
        request: Request,
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce_limit(
            request,
            "assist",
            identity,
            limit=60,
            window_seconds=3600,
        )
        submission = submission.model_copy(update={"responder_id": identity})
        post = repo.add_response(post_id, submission)
        if post is None:
            raise HTTPException(404, "没有找到这条声音线索")
        return post.model_dump(mode="json")

    @router.delete("/posts/{post_id}", status_code=204)
    def withdraw(
        post_id: str,
        request: Request,
        authorization: str | None = Header(default=None),
    ) -> None:
        identity = identity_from(authorization)
        enforce_limit(
            request,
            "withdraw",
            identity,
            limit=20,
            window_seconds=3600,
        )
        post = repo.get_post(post_id, requester_id=identity)
        if post is None or not post.owned_by_requester or not repo.withdraw(post_id, identity):
            raise HTTPException(404, "没有找到可撤回的声音线索")
        media_name = Path(urlparse(post.audio_url).path).name
        if re.fullmatch(r"[a-f0-9]{32}\.(wav|mp3|m4a|ogg|aac)", media_name):
            store.delete(media_name)

    return router
