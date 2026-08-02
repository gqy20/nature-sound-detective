from __future__ import annotations

import json
import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from app.config import JOB_DIR
from app.creation_service import CreationService
from app.pipeline import AnalysisPipeline
from app.observability import current_trace_id, get_logger, log_event, log_exception, trace_context


logger = get_logger("jobs")


class JobStore:
    def __init__(self) -> None:
        self._jobs: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="nature-job")
        self._creation_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="creation-job")
        self._pipeline: AnalysisPipeline | None = None
        self._load_existing()

    def _load_existing(self) -> None:
        """Restore recent completed jobs so the local sound album survives restarts."""
        for path in JOB_DIR.glob("*.json"):
            try:
                job = json.loads(path.read_text(encoding="utf-8"))
                if not isinstance(job, dict) or not job.get("id") or not job.get("audio_path"):
                    continue
                if job.get("status") not in {"completed", "failed"}:
                    job["status"] = "failed"
                    job["stage_message"] = "服务重启，请重新提交录音"
                    job["error"] = "上一次识别没有完成"
                    self._write(job)
                creation = job.get("creation") or {"status": "idle", "stage_message": ""}
                if creation.get("status") in {
                    "queued", "generating_music", "generating_narration",
                    "generating_video", "composing_video"
                }:
                    music_path = Path(creation.get("music_path", ""))
                    if creation.get("music_path") and music_path.exists():
                        resumable = bool(creation.get("wan_task_id"))
                        creation.update(
                            status="partial",
                            stage_message=(
                                "音乐已恢复，可以继续查询原视频任务" if resumable
                                else "音乐已恢复，视频需要重新生成"
                            ),
                            video_error=(
                                "服务曾在视频生成期间重启，原任务ID已保留" if resumable
                                else "服务曾在视频生成期间重启"
                            ),
                        )
                    else:
                        creation = {
                            "status": "failed",
                            "stage_message": "创作曾被服务重启中断",
                            "error": "请重新开始创作",
                        }
                    job["creation"] = creation
                    self._write(job)
                self._jobs[job["id"]] = job
            except (OSError, json.JSONDecodeError, KeyError):
                continue

    def _write(self, job: dict[str, Any]) -> None:
        path = JOB_DIR / f"{job['id']}.json"
        path.write_text(json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8")

    def create(self, audio_path: Path, location: str, duration: float) -> dict[str, Any]:
        job_id = uuid4().hex
        now = datetime.now(timezone.utc).isoformat()
        job = {
            "id": job_id,
            "trace_id": current_trace_id(),
            "status": "queued",
            "stage_message": "正在准备录音",
            "created_at": now,
            "updated_at": now,
            "location": location,
            "duration_seconds": duration,
            "audio_url": f"/api/jobs/{job_id}/audio",
            "audio_path": str(audio_path),
            "result": None,
            "error": None,
            "creation": {"status": "idle", "stage_message": ""},
        }
        with self._lock:
            self._jobs[job_id] = job
            self._write(job)
        self._executor.submit(self._run, job_id)
        log_event(logger, logging.INFO, "analysis_job_queued", job_id=job_id)
        return self.public(job)

    def _update(self, job_id: str, **changes: Any) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return False
            job.update(changes)
            job["updated_at"] = datetime.now(timezone.utc).isoformat()
            self._write(job)
            return True

    def _run(self, job_id: str) -> None:
        job = self._jobs[job_id]
        with trace_context(job.get("trace_id", job_id)):
            self._run_with_trace(job_id, job)

    def _run_with_trace(self, job_id: str, job: dict[str, Any]) -> None:
        try:
            if self._pipeline is None:
                self._pipeline = AnalysisPipeline()
            def progress(status: str, message: str) -> None:
                self._update(job_id, status=status, stage_message=message)
                log_event(logger, logging.INFO, "analysis_job_progress", job_id=job_id, stage=status)

            result = self._pipeline.run(Path(job["audio_path"]), job["location"], progress)
            self._update(
                job_id,
                status="completed",
                stage_message="声音卡片制作完成",
                result=result,
            )
            log_event(logger, logging.INFO, "analysis_job_completed", job_id=job_id)
        except Exception as exc:
            log_exception(logger, "analysis_job_failed", job_id=job_id)
            self._update(
                job_id,
                status="failed",
                stage_message="这次没有听清",
                error=str(exc),
            )

    def get(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return self.public(job) if job else None

    @staticmethod
    def public(job: dict[str, Any]) -> dict[str, Any]:
        value = json.loads(json.dumps(job))
        value.pop("audio_path", None)
        creation = value.get("creation") or {}
        for key in ("music_path", "narration_path", "video_path"):
            creation.pop(key, None)
        return value

    def start_creation(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return None
            if job.get("status") != "completed":
                raise ValueError("声音识别尚未完成")
            status = (job.get("creation") or {}).get("status", "idle")
            if status in {
                "queued", "generating_music", "generating_narration",
                "generating_video", "composing_video"
            }:
                return self.public(job)
            previous = job.get("creation") or {}
            job["creation"] = {
                **previous, "status": "queued", "stage_message": "准备创作声音短片",
                "error": "", "video_error": "",
            }
            self._write(job)
        self._creation_executor.submit(self._run_creation, job_id)
        log_event(logger, logging.INFO, "creation_job_queued", job_id=job_id)
        return self.get(job_id)

    def _run_creation(self, job_id: str) -> None:
        job = self._jobs[job_id]
        with trace_context(job.get("trace_id", job_id)):
            self._run_creation_with_trace(job_id, job)

    def _run_creation_with_trace(self, job_id: str, job: dict[str, Any]) -> None:
        try:
            service = CreationService()

            def progress(status: str, message: str, details: dict[str, Any] | None = None) -> None:
                creation = {**(job.get("creation") or {}), **(details or {})}
                creation.update(status=status, stage_message=message)
                self._update(job_id, creation=creation)
                log_event(logger, logging.INFO, "creation_job_progress", job_id=job_id, stage=status)

            creation = service.create(
                job_id, job["result"], Path(job["audio_path"]), job["location"], progress,
                previous_creation=job.get("creation") or {},
            )
            if not self._update(job_id, creation=creation):
                for key in ("music_path", "narration_path", "video_path"):
                    if creation.get(key):
                        Path(creation[key]).unlink(missing_ok=True)
            log_event(logger, logging.INFO, "creation_job_completed", job_id=job_id)
        except Exception as exc:
            log_exception(logger, "creation_job_failed", job_id=job_id)
            self._update(job_id, creation={
                "status": "failed", "stage_message": "创作没有完成", "error": str(exc)
            })

    def creation_media_path(self, job_id: str, kind: str) -> Path | None:
        with self._lock:
            job = self._jobs.get(job_id)
            path = (job or {}).get("creation", {}).get(f"{kind}_path")
            return Path(path) if path else None

    def audio_path(self, job_id: str) -> Path | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return Path(job["audio_path"]) if job else None

    def delete(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.pop(job_id, None)
        if not job:
            return False
        Path(job["audio_path"]).unlink(missing_ok=True)
        for key in ("music_path", "narration_path", "video_path"):
            media_path = (job.get("creation") or {}).get(key)
            if media_path:
                Path(media_path).unlink(missing_ok=True)
        (JOB_DIR / f"{job_id}.json").unlink(missing_ok=True)
        return True
