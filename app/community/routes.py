from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import ValidationError

from app.community.models import AssistSubmission, PublicationMetadata, PublicationResult
from app.community.repository import CommunityRepository, repository_from_environment
from app.config import COMMUNITY_MEDIA_DIR


MAX_COMMUNITY_AUDIO_BYTES = 4 * 1024 * 1024


def build_community_router(repository: CommunityRepository | None = None) -> APIRouter:
    repo = repository or repository_from_environment()
    router = APIRouter(prefix="/api/community", tags=["community"])

    @router.get("/areas")
    def areas():
        return [item.model_dump(mode="json") for item in repo.area_summaries()]

    @router.get("/posts")
    def list_posts(area_id: str | None = None, x_device_id: str | None = Header(default=None)):
        return [item.model_dump(mode="json") for item in repo.list_posts(area_id=area_id, requester_id=x_device_id)]

    @router.get("/posts/{post_id}")
    def get_post(post_id: str, x_device_id: str | None = Header(default=None)):
        post = repo.get_post(post_id, requester_id=x_device_id)
        if post is None:
            raise HTTPException(404, "没有找到这条声音线索")
        return post.model_dump(mode="json")

    @router.post("/posts", status_code=201, response_model=PublicationResult)
    async def create_post(metadata: str = Form(...), audio: UploadFile = File(...)):
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
        COMMUNITY_MEDIA_DIR.mkdir(parents=True, exist_ok=True)
        media_name = f"{uuid4().hex}{suffix}"
        destination = COMMUNITY_MEDIA_DIR / media_name
        destination.write_bytes(payload)
        audio_url = f"/api/community/media/{media_name}"
        try:
            post = repo.create_post(parsed, audio_url)
        except PermissionError as exc:
            destination.unlink(missing_ok=True)
            raise HTTPException(403, str(exc)) from exc
        except Exception:
            destination.unlink(missing_ok=True)
            raise
        return PublicationResult(post=post)

    @router.get("/media/{media_name}")
    def media(media_name: str):
        if not re.fullmatch(r"[a-f0-9]{32}\.(wav|mp3|m4a|ogg|aac)", media_name):
            raise HTTPException(404, "声音片段不存在")
        path = COMMUNITY_MEDIA_DIR / media_name
        if not path.is_file():
            raise HTTPException(404, "声音片段不存在")
        return FileResponse(path)

    @router.post("/posts/{post_id}/responses")
    def add_response(post_id: str, submission: AssistSubmission):
        post = repo.add_response(post_id, submission)
        if post is None:
            raise HTTPException(404, "没有找到这条声音线索")
        return post.model_dump(mode="json")

    @router.delete("/posts/{post_id}", status_code=204)
    def withdraw(post_id: str, x_device_id: str | None = Header(default=None)) -> None:
        post = repo.get_post(post_id, requester_id=x_device_id) if x_device_id else None
        if post is None or not post.owned_by_requester or not repo.withdraw(post_id, x_device_id):
            raise HTTPException(404, "没有找到可撤回的声音线索")
        media_name = Path(urlparse(post.audio_url).path).name
        if re.fullmatch(r"[a-f0-9]{32}\.(wav|mp3|m4a|ogg|aac)", media_name):
            (COMMUNITY_MEDIA_DIR / media_name).unlink(missing_ok=True)

    return router
