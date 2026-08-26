from __future__ import annotations

import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.yamnet_service import LABEL_PATH, MODEL_PATH, YamNetAnalyzer
from app.community.routes import build_community_router
from app.family_sessions.routes import build_family_session_router
from app.field_observations import SCHEMA_PATH
from app.observability import get_logger, install_observability, log_exception
from app.investigation import apply_observation, apply_structured_observations, build_investigation
from app.result_fusion import fuse_results
from app.story_service import AnimalStoryService


MAX_UPLOAD_BYTES = 15 * 1024 * 1024
app = FastAPI(title="自然声探员 Cloud API", version="0.1.0")
install_observability(app, "api.vercel")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["X-Trace-ID"],
)
_analyzer: YamNetAnalyzer | None = None
logger = get_logger("api.analysis")
app.include_router(build_community_router())
app.include_router(build_family_session_router())


def _get_analyzer() -> YamNetAnalyzer:
    global _analyzer
    if _analyzer is None:
        _analyzer = YamNetAnalyzer()
    return _analyzer


class FeedbackSubmission(BaseModel):
    job_id: str = Field(max_length=80)
    is_correct: bool
    corrected_type: str | None = Field(default=None, max_length=40)


class StatelessObservationSubmission(BaseModel):
    investigation: dict[str, Any]
    question_id: str = Field(min_length=1, max_length=80)
    choice: str = Field(min_length=1, max_length=40)
    note: str = Field(default="", max_length=300)


class StatelessStorySubmission(BaseModel):
    result: dict[str, Any]
    candidate_id: str = Field(min_length=1, max_length=120)
    story_type: str = Field(default="animal_life", max_length=40)
    location: str = Field(default="杭州", max_length=80)
    investigation: dict[str, Any]


class StatelessStructuredObservationsSubmission(BaseModel):
    investigation: dict[str, Any]
    candidate_id: str = Field(min_length=1, max_length=120)
    selections: dict[str, list[str]]


@app.get("/")
def root() -> dict[str, str]:
    return {"service": "nature-sound-detective-cloud", "status": "ok", "mode": "yamnet-only"}


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "mode": "vercel-yamnet-only",
        "revision": os.getenv("VERCEL_GIT_COMMIT_SHA", "")[:7],
        "assets": {
            "yamnet_model": MODEL_PATH.is_file(),
            "yamnet_labels": LABEL_PATH.is_file(),
            "field_observations": SCHEMA_PATH.is_file(),
        },
    }


@app.post("/api/analyze")
async def analyze(audio: UploadFile = File(...), location: str = Form("杭州")) -> dict[str, Any]:
    payload = await audio.read(MAX_UPLOAD_BYTES + 1)
    if len(payload) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "录音文件不能超过15MB")
    if len(payload) < 44 or payload[:4] != b"RIFF" or payload[8:12] != b"WAVE":
        raise HTTPException(422, "云端识别需要浏览器生成的WAV录音")
    temp_path: Path | None = None
    try:
        with NamedTemporaryFile(prefix="nature-", suffix=".wav", dir="/tmp", delete=False) as handle:
            handle.write(payload)
            temp_path = Path(handle.name)
        general = _get_analyzer().analyze(temp_path, location.strip()[:80] or "杭州")
        result = fuse_results(general, {
            "model": "云端轻量版未启用 BirdNET",
            "scope": "声音大类识别；鸟种候选请使用本地完整版",
            "detections": [],
        })
    except HTTPException:
        raise
    except Exception as exc:
        log_exception(logger, "cloud_analysis_failed", model="YAMNet tflite-1")
        raise HTTPException(502, "声音模型暂时无法完成分析") from exc
    finally:
        if temp_path:
            temp_path.unlink(missing_ok=True)
    job_id = uuid4().hex
    investigation = build_investigation(
        result,
        location.strip()[:80] or "杭州",
        investigation_id=f"cloud-{job_id}",
    )
    return {
        "id": job_id,
        "status": "completed",
        "stage_message": "声音卡片制作完成",
        "location": location.strip()[:80] or "杭州",
        "audio_url": "",
        "result": result,
        "investigation": investigation,
        "error": None,
        "creation": {"status": "unavailable", "stage_message": "云端展示版暂不生成媒体"},
        "capabilities": {
            "birdnet": False,
            "creation": False,
            "feedback": False,
            "persistence": False,
            "investigation": True,
        },
        "deployment": "vercel-yamnet-only",
    }


@app.post("/api/investigation/observations")
def submit_stateless_observation(payload: StatelessObservationSubmission) -> dict[str, Any]:
    try:
        return apply_observation(
            payload.investigation,
            question_id=payload.question_id,
            choice=payload.choice,
            note=payload.note,
            source="cloud-api",
        )
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc


@app.post("/api/investigation/structured-observations")
def submit_stateless_structured_observations(payload: StatelessStructuredObservationsSubmission) -> dict[str, Any]:
    try:
        return apply_structured_observations(
            payload.investigation,
            candidate_id=payload.candidate_id,
            selections=payload.selections,
            source="cloud-api",
        )
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc


@app.post("/api/stories")
def create_stateless_story(payload: StatelessStorySubmission) -> dict[str, Any]:
    try:
        return AnimalStoryService().create(
            result=payload.result,
            candidate_id=payload.candidate_id,
            location=payload.location,
            story_type=payload.story_type,
            observations=[
                item for item in payload.investigation.get("observations") or []
                if item.get("candidate_id") == payload.candidate_id
            ],
        )
    except ValueError as exc:
        raise HTTPException(409, str(exc)) from exc


@app.post("/api/feedback", status_code=202)
def feedback(_: FeedbackSubmission) -> dict[str, Any]:
    return {"status": "accepted", "persisted": False}
