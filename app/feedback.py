from __future__ import annotations

from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
from typing import Any
from uuid import uuid4


VALID_DECISIONS = {"correct", "wrong", "uncertain"}


def save_feedback_record(
    submission: dict[str, Any],
    *,
    job: dict[str, Any] | None,
    feedback_dir: Path,
) -> dict[str, Any]:
    decision = submission.get("decision")
    if decision not in VALID_DECISIONS:
        decision = "correct" if submission.get("is_correct") is True else "wrong"
    feedback_id = uuid4().hex
    audio_retained = False
    retained_path: str | None = None
    if submission.get("consent_to_retain_audio"):
        if not job:
            raise ValueError("找不到对应分析任务，无法留存音频")
        source = Path(str(job.get("audio_path", "")))
        if not source.is_file():
            raise ValueError("对应分析音频已过期，无法留存")
        audio_dir = feedback_dir / "audio"
        audio_dir.mkdir(parents=True, exist_ok=True)
        destination = audio_dir / f"{feedback_id}{source.suffix.lower() or '.wav'}"
        shutil.copy2(source, destination)
        audio_retained = True
        retained_path = str(destination)
    result = (job or {}).get("result") or {}
    payload = {
        "id": feedback_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "job_id": submission.get("job_id", ""),
        "recording_id": submission.get("recording_id") or submission.get("job_id", ""),
        "decision": decision,
        "corrected_type": submission.get("corrected_type"),
        "corrected_taxon_id": submission.get("corrected_taxon_id"),
        "consent_to_retain_audio": bool(submission.get("consent_to_retain_audio")),
        "audio_retained": audio_retained,
        "retained_audio_path": retained_path,
        "review_status": "user_reported",
        "model_snapshot": result.get("models", {}),
        "prediction_snapshot": result.get("detections", []),
        "location": (job or {}).get("location"),
    }
    feedback_dir.mkdir(parents=True, exist_ok=True)
    destination = feedback_dir / f"{feedback_id}.json"
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(destination)
    return {"id": feedback_id, "status": "saved", "audio_retained": audio_retained}
