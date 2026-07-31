from __future__ import annotations

import json
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from app.config import JOB_DIR
from app.pipeline import AnalysisPipeline


class JobStore:
    def __init__(self) -> None:
        self._jobs: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="nature-job")
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
        }
        with self._lock:
            self._jobs[job_id] = job
            self._write(job)
        self._executor.submit(self._run, job_id)
        return self.public(job)

    def _update(self, job_id: str, **changes: Any) -> None:
        with self._lock:
            job = self._jobs[job_id]
            job.update(changes)
            job["updated_at"] = datetime.now(timezone.utc).isoformat()
            self._write(job)

    def _run(self, job_id: str) -> None:
        try:
            if self._pipeline is None:
                self._pipeline = AnalysisPipeline()
            job = self._jobs[job_id]

            def progress(status: str, message: str) -> None:
                self._update(job_id, status=status, stage_message=message)

            result = self._pipeline.run(Path(job["audio_path"]), job["location"], progress)
            self._update(
                job_id,
                status="completed",
                stage_message="声音卡片制作完成",
                result=result,
            )
        except Exception as exc:
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
        return {key: value for key, value in job.items() if key != "audio_path"}

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
        (JOB_DIR / f"{job_id}.json").unlink(missing_ok=True)
        return True
