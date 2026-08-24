from __future__ import annotations

import json
import logging
import math
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from app.config import JOB_DIR
from app.creation_service import CreationService
from app.investigation import apply_observation, build_investigation
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
        self._pipeline_lock = threading.Lock()
        self._model_status: dict[str, Any] = {
            "status": "idle",
            "duration_ms": None,
            "components": {},
            "error": None,
        }
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
                if job.get("status") == "completed" and isinstance(job.get("result"), dict) and not job.get("investigation"):
                    job["investigation"] = build_investigation(
                        job["result"],
                        str(job.get("location") or "杭州"),
                        investigation_id=f"job-{job['id']}",
                        created_at=str(job.get("updated_at") or job.get("created_at") or datetime.now(timezone.utc).isoformat()),
                    )
                    self._write(job)
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

    def create(
        self,
        audio_path: Path,
        location: str,
        duration: float,
        *,
        general_audio_path: Path | None = None,
    ) -> dict[str, Any]:
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
            "general_audio_path": str(general_audio_path or audio_path),
            "result": None,
            "investigation": None,
            "partial_result": None,
            "analysis_progress": {
                "processed_windows": 0,
                "total_windows": max(1, math.ceil(duration / 3)),
            },
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
            pipeline = self._get_pipeline()

            def progress(
                status: str,
                message: str,
                details: dict[str, Any] | None = None,
            ) -> None:
                self._update(job_id, status=status, stage_message=message, **(details or {}))
                log_event(logger, logging.INFO, "analysis_job_progress", job_id=job_id, stage=status)

            result = pipeline.run(
                Path(job["audio_path"]),
                job["location"],
                progress,
                general_audio_path=Path(job.get("general_audio_path") or job["audio_path"]),
            )
            self._update(
                job_id,
                status="completed",
                stage_message="声音卡片制作完成",
                result=result,
                investigation=build_investigation(
                    result,
                    str(job.get("location") or "杭州"),
                    investigation_id=f"job-{job_id}",
                ),
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

    def _get_pipeline(self) -> AnalysisPipeline:
        if self._pipeline is None:
            with self._pipeline_lock:
                if self._pipeline is None:
                    self._pipeline = AnalysisPipeline()
        return self._pipeline

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        with self._pipeline_lock:
            self._model_status = {
                "status": "loading",
                "duration_ms": None,
                "components": {},
                "error": None,
            }
            try:
                if self._pipeline is None:
                    self._pipeline = AnalysisPipeline()
                report = self._pipeline.preload()
                self._model_status = {**report, "error": None}
            except Exception as exc:
                self._model_status = {
                    "status": "failed",
                    "duration_ms": round((time.perf_counter() - started) * 1000),
                    "components": {},
                    "error": str(exc),
                }
                raise
            return json.loads(json.dumps(self._model_status))

    def model_status(self) -> dict[str, Any]:
        with self._pipeline_lock:
            return json.loads(json.dumps(self._model_status))

    def get(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return self.public(job) if job else None

    def submit_observation(
        self,
        job_id: str,
        *,
        question_id: str,
        choice: str,
        note: str = "",
        source: str = "user",
    ) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            if not job:
                return None
            investigation = job.get("investigation")
            if not isinstance(investigation, dict):
                raise ValueError("这次声音分析还没有进入调查阶段")
            updated = apply_observation(
                investigation,
                question_id=question_id,
                choice=choice,
                note=note,
                source=source,
            )
            job["investigation"] = updated
            job["updated_at"] = datetime.now(timezone.utc).isoformat()
            self._write(job)
            return self.public(job)

    @staticmethod
    def public(job: dict[str, Any]) -> dict[str, Any]:
        value = json.loads(json.dumps(job))
        value.pop("audio_path", None)
        value.pop("general_audio_path", None)
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
        general_path = Path(job.get("general_audio_path") or job["audio_path"])
        if general_path != Path(job["audio_path"]):
            general_path.unlink(missing_ok=True)
        for key in ("music_path", "narration_path", "video_path"):
            media_path = (job.get("creation") or {}).get(key)
            if media_path:
                Path(media_path).unlink(missing_ok=True)
        (JOB_DIR / f"{job_id}.json").unlink(missing_ok=True)
        return True
