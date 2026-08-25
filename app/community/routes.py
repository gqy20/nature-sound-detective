from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

from fastapi import APIRouter, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import ValidationError

from app.community.auth import CommunityAuth, InMemoryRateLimiter, InvalidCommunityToken
from app.community.catalog import PILOT_ROUTES, park_by_id, zone_by_id
from app.community.models import ExplorationRoute
from app.community.insights import build_daily_brief
from app.community.models import (
    AssistSubmission,
    DeviceSessionRequest,
    DeviceSessionResponse,
    PublicationMetadata,
    PublicationResult,
    CommunityMediaAsset,
)
from app.community.repository import CommunityRepository, repository_from_environment
from app.community.storage import (
    CommunityMediaStore,
    CommunityMediaUnavailable,
    media_store_from_environment,
)
from app.config import COMMUNITY_MEDIA_DIR


MAX_COMMUNITY_AUDIO_BYTES = 4 * 1024 * 1024
MAX_COMMUNITY_DISPLAY_MEDIA_BYTES = 25 * 1024 * 1024


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

    @router.get("/parks")
    def parks():
        return [item.model_dump(mode="json") for item in repo.park_summaries()]

    @router.get("/sites")
    def sites(park_id: str | None = None):
        if park_id and park_by_id(park_id) is None:
            raise HTTPException(404, "没有找到这个试点公园")
        return [item.model_dump(mode="json") for item in repo.park_sites(park_id)]

    @router.get("/parks/{park_id}/ecology-snapshot")
    def ecology_snapshot(park_id: str, days: int = 7):
        if not 1 <= days <= 90:
            raise HTTPException(422, "趋势周期必须在1至90天之间")
        try:
            return repo.ecology_snapshot(park_id, days).model_dump(mode="json")
        except KeyError as exc:
            raise HTTPException(404, "没有找到这个试点公园") from exc

    @router.get("/parks/{park_id}/daily-brief")
    def daily_brief(park_id: str, days: int = 7):
        if not 1 <= days <= 90:
            raise HTTPException(422, "资讯周期必须在1至90天之间")
        try:
            return build_daily_brief(
                repo.ecology_snapshot(park_id, days)
            ).model_dump(mode="json")
        except KeyError as exc:
            raise HTTPException(404, "没有找到这个试点公园") from exc

    @router.get("/parks/{park_id}/routes")
    def exploration_routes(park_id: str):
        if park_by_id(park_id) is None:
            raise HTTPException(404, "没有找到这个试点公园")
        return [
            ExplorationRoute.model_validate(item).model_dump(mode="json")
            for item in PILOT_ROUTES
            if item["park_id"] == park_id
        ]

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
        if parsed.park_id:
            park = park_by_id(parsed.park_id)
            zone = zone_by_id(parsed.park_id, parsed.zone_id)
            if park is None or zone is None:
                raise HTTPException(422, "公园或分区不在当前试点范围")
            if park["area_id"] != parsed.area_id:
                raise HTTPException(422, "公园与行政区域不一致")
            expected_site_id = f"{parsed.park_id}:{parsed.zone_id}"
            if parsed.site_id and parsed.site_id != expected_site_id:
                raise HTTPException(422, "观察点与公园分区不一致")
            is_demo = parsed.model_snapshot.get("demo") is True
            parsed = parsed.model_copy(
                update={
                    "site_id": expected_site_id,
                    "ecology_eligible": (
                        bool(parsed.audio_quality.get("usable", False))
                        and not bool(parsed.audio_quality.get("weak_signal", False))
                        and bool(parsed.audio_quality.get("ecology_usable", True))
                        and not is_demo
                    ),
                }
            )
        else:
            parsed = parsed.model_copy(update={"ecology_eligible": False})
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
        if not re.fullmatch(r"[a-f0-9]{32}\.(wav|mp3|m4a|ogg|aac|jpg|jpeg|png|webp|mp4)", media_name):
            raise HTTPException(404, "声音片段不存在")
        path = store.local_path(media_name)
        if path is None:
            raise HTTPException(404, "声音片段不存在")
        return FileResponse(path)

    @router.post("/posts/{post_id}/media", status_code=201)
    async def add_post_media(
        post_id: str,
        request: Request,
        file: UploadFile = File(...),
        media_type: str = Form(...),
        source_type: str = Form(...),
        provider: str | None = Form(default=None),
        model: str | None = Form(default=None),
        authorization: str | None = Header(default=None),
    ):
        identity = identity_from(authorization)
        enforce_limit(request, "publish-media", identity, limit=16, window_seconds=3600)
        post = repo.get_post(post_id, requester_id=identity)
        if post is None or not post.owned_by_requester:
            raise HTTPException(404, "没有找到可添加媒体的社区记录")
        suffix = Path(file.filename or "asset").suffix.lower()
        allowed = {
            "image": {".jpg", ".jpeg", ".png", ".webp"},
            "video": {".mp4"},
            "thumbnail": {".jpg", ".jpeg", ".png", ".webp"},
        }
        if media_type not in allowed or suffix not in allowed[media_type]:
            raise HTTPException(415, "展示媒体格式不受支持")
        if source_type not in {"original", "ai_generated", "composed"}:
            raise HTTPException(422, "媒体来源类型无效")
        payload = await file.read(MAX_COMMUNITY_DISPLAY_MEDIA_BYTES + 1)
        if len(payload) > MAX_COMMUNITY_DISPLAY_MEDIA_BYTES:
            raise HTTPException(413, "图片或视频不能超过25MB")
        if not payload:
            raise HTTPException(422, "展示媒体为空")
        media_name = f"{uuid4().hex}{suffix}"
        try:
            url = store.save(
                media_name,
                payload,
                file.content_type or "application/octet-stream",
            )
            asset = CommunityMediaAsset(
                id=uuid4().hex,
                media_type=media_type,
                source_type=source_type,
                url=url,
                provider=provider,
                model=model,
                moderation_status="approved",
            )
            if not repo.add_media_asset(post_id, identity, asset):
                store.delete(media_name)
                raise HTTPException(404, "没有找到可添加媒体的社区记录")
            return asset.model_dump(mode="json")
        except CommunityMediaUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc

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
        for asset in post.media_assets:
            asset_name = Path(urlparse(asset.url).path).name
            if re.fullmatch(r"[a-f0-9]{32}\.(jpg|jpeg|png|webp|mp4)", asset_name):
                store.delete(asset_name)

    return router
