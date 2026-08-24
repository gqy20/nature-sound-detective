from __future__ import annotations

import asyncio
import re
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from app.audio import AudioPreparationError, duration_seconds, prepare_audio
from app.community.routes import build_community_router
from app.config import (
    ALLOWED_EXTENSIONS,
    FEEDBACK_DIR,
    MAX_UPLOAD_BYTES,
    MODEL_PRELOAD_ENABLED,
    STATIC_DIR,
    UPLOAD_DIR,
    cleanup_expired_runtime,
    ensure_runtime_dirs,
)
from app.jobs import JobStore
from app.feedback import save_feedback_record
from app.observability import install_observability


ensure_runtime_dirs()
cleanup_expired_runtime()


@asynccontextmanager
async def lifespan(_: FastAPI):
    if MODEL_PRELOAD_ENABLED:
        try:
            await asyncio.to_thread(jobs.preload)
        except Exception:
            # A preload failure is observable through /api/health, while analysis
            # still gets a chance to retry or use its existing fallback behavior.
            pass
    cleanup_task = asyncio.create_task(_cleanup_loop())
    try:
        yield
    finally:
        cleanup_task.cancel()
        try:
            await cleanup_task
        except asyncio.CancelledError:
            pass


async def _cleanup_loop() -> None:
    while True:
        await asyncio.to_thread(cleanup_expired_runtime)
        await asyncio.sleep(15 * 60)


app = FastAPI(title="自然声探员 MVP", version="0.1.0", lifespan=lifespan)
install_observability(app, "api.local")
app.include_router(build_community_router())
jobs = JobStore()
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


class FeedbackSubmission(BaseModel):
    job_id: str = Field(max_length=80)
    recording_id: str | None = Field(default=None, max_length=80)
    is_correct: bool | None = None
    decision: str | None = Field(default=None, max_length=20)
    corrected_type: str | None = Field(default=None, max_length=40)
    corrected_taxon_id: str | None = Field(default=None, max_length=80)
    consent_to_retain_audio: bool = False


class ObservationSubmission(BaseModel):
    question_id: str = Field(min_length=1, max_length=80)
    choice: str = Field(min_length=1, max_length=40)
    note: str = Field(default="", max_length=300)


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "models": jobs.model_status()}


@app.post("/api/analyze", status_code=202)
async def analyze(
    audio: UploadFile = File(...),
    location: str = Form("杭州"),
) -> dict:
    cleanup_expired_runtime()
    suffix = Path(audio.filename or "recording.webm").suffix.lower()
    if suffix not in ALLOWED_EXTENSIONS:
        raise HTTPException(415, "暂不支持这种音频格式")

    safe_stem = re.sub(r"[^A-Za-z0-9_-]", "_", Path(audio.filename or "recording").stem)[:40]
    token = __import__("uuid").uuid4().hex
    source_path = UPLOAD_DIR / f"{token}_{safe_stem}{suffix}"
    total = 0
    with source_path.open("wb") as handle:
        while chunk := await audio.read(1024 * 1024):
            total += len(chunk)
            if total > MAX_UPLOAD_BYTES:
                handle.close()
                source_path.unlink(missing_ok=True)
                raise HTTPException(413, "录音文件不能超过15MB")
            handle.write(chunk)

    prepared_path = UPLOAD_DIR / f"{token}_bioacoustic.wav"
    general_path = UPLOAD_DIR / f"{token}_general.wav"
    try:
        await run_in_threadpool(prepare_audio, source_path, prepared_path, general_path)
    except AudioPreparationError as exc:
        source_path.unlink(missing_ok=True)
        prepared_path.unlink(missing_ok=True)
        general_path.unlink(missing_ok=True)
        raise HTTPException(422, str(exc)) from exc
    finally:
        if source_path != prepared_path:
            source_path.unlink(missing_ok=True)

    duration = await run_in_threadpool(duration_seconds, prepared_path)
    return jobs.create(
        prepared_path,
        location.strip()[:80] or "杭州",
        duration,
        general_audio_path=general_path,
    )


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str) -> dict:
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(404, "没有找到这次声音分析")
    return job


@app.post("/api/jobs/{job_id}/investigation/observations")
def submit_investigation_observation(job_id: str, observation: ObservationSubmission) -> dict:
    try:
        job = jobs.submit_observation(
            job_id,
            question_id=observation.question_id,
            choice=observation.choice,
            note=observation.note,
            source="api",
        )
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
    if not job:
        raise HTTPException(404, "没有找到这次声音调查")
    return job


@app.get("/api/jobs/{job_id}/audio")
def get_job_audio(job_id: str) -> FileResponse:
    path = jobs.audio_path(job_id)
    if not path or not path.exists():
        raise HTTPException(404, "录音不存在")
    return FileResponse(path, media_type="audio/wav", filename="nature-recording.wav")


@app.post("/api/jobs/{job_id}/creation", status_code=202)
def start_creation(job_id: str) -> dict:
    try:
        job = jobs.start_creation(job_id)
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
    if not job:
        raise HTTPException(404, "没有找到这次声音分析")
    return job


@app.get("/api/jobs/{job_id}/creation/music")
def get_creation_music(job_id: str) -> FileResponse:
    path = jobs.creation_media_path(job_id, "music")
    if not path or not path.exists():
        raise HTTPException(404, "自然声音乐还没有生成")
    return FileResponse(path, media_type="audio/mpeg", filename="nature-remix.mp3")


@app.get("/api/jobs/{job_id}/creation/narration")
def get_creation_narration(job_id: str) -> FileResponse:
    path = jobs.creation_media_path(job_id, "narration")
    if not path or not path.exists():
        raise HTTPException(404, "科普旁白还没有生成")
    return FileResponse(path, media_type="audio/mpeg", filename="nature-narration.mp3")


@app.get("/api/jobs/{job_id}/creation/video")
def get_creation_video(job_id: str) -> FileResponse:
    path = jobs.creation_media_path(job_id, "video")
    if not path or not path.exists():
        raise HTTPException(404, "科普短片还没有生成")
    return FileResponse(path, media_type="video/mp4", filename="nature-postcard.mp4")


@app.delete("/api/jobs/{job_id}", status_code=204)
def delete_job(job_id: str) -> None:
    if not jobs.delete(job_id):
        raise HTTPException(404, "没有找到这次声音分析")


@app.post("/api/feedback", status_code=201)
def save_feedback(feedback: FeedbackSubmission) -> dict[str, Any]:
    try:
        return save_feedback_record(
            feedback.model_dump(),
            job=jobs.get(feedback.job_id),
            feedback_dir=FEEDBACK_DIR,
        )
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc
