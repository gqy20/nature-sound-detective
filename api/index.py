from __future__ import annotations

import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.qwen_service import QwenNatureAnalyzer
from app.result_fusion import fuse_results


MAX_UPLOAD_BYTES = 15 * 1024 * 1024
app = FastAPI(title="自然声探员 Cloud API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in os.getenv("CORS_ORIGINS", "*").split(",")],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)
_analyzer: QwenNatureAnalyzer | None = None


def _get_analyzer() -> QwenNatureAnalyzer:
    global _analyzer
    if _analyzer is None:
        _analyzer = QwenNatureAnalyzer()
    return _analyzer


class FeedbackSubmission(BaseModel):
    job_id: str = Field(max_length=80)
    is_correct: bool
    corrected_type: str | None = Field(default=None, max_length=40)


@app.get("/")
def root() -> dict[str, str]:
    return {"service": "nature-sound-detective-cloud", "status": "ok", "mode": "qwen-only"}


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "mode": "vercel-qwen-only"}


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
        qwen = _get_analyzer().analyze(temp_path, location.strip()[:80] or "杭州")
        result = fuse_results(qwen, {
            "model": "云端轻量版未启用 BirdNET",
            "scope": "声音大类识别；鸟种候选请使用本地完整版",
            "detections": [],
        })
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(502, f"声音模型调用失败：{exc}") from exc
    finally:
        if temp_path:
            temp_path.unlink(missing_ok=True)
    return {
        "id": uuid4().hex,
        "status": "completed",
        "stage_message": "声音卡片制作完成",
        "location": location.strip()[:80] or "杭州",
        "audio_url": "",
        "result": result,
        "error": None,
        "creation": {"status": "unavailable", "stage_message": "云端展示版暂不生成媒体"},
        "capabilities": {"birdnet": False, "creation": False, "feedback": False, "persistence": False},
        "deployment": "vercel-qwen-only",
    }


@app.post("/api/feedback", status_code=202)
def feedback(_: FeedbackSubmission) -> dict[str, Any]:
    return {"status": "accepted", "persisted": False}
