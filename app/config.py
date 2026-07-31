from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATIC_DIR = ROOT / "app" / "static"
RUNTIME_DIR = ROOT / "outputs" / "mvp"
UPLOAD_DIR = RUNTIME_DIR / "uploads"
JOB_DIR = RUNTIME_DIR / "jobs"
FEEDBACK_DIR = RUNTIME_DIR / "feedback"
GENERATED_DIR = RUNTIME_DIR / "generated"

MAX_UPLOAD_BYTES = 15 * 1024 * 1024
MAX_ANALYSIS_SECONDS = 20
RETENTION_HOURS = 24
ALLOWED_EXTENSIONS = {
    ".wav", ".mp3", ".aac", ".amr", ".3gp", ".3gpp",
    ".m4a", ".mp4", ".ogg", ".opus", ".webm",
}


def ensure_runtime_dirs() -> None:
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    JOB_DIR.mkdir(parents=True, exist_ok=True)
    FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)


def cleanup_expired_runtime() -> int:
    """Delete expired MVP recordings and job metadata from known runtime folders."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=RETENTION_HOURS)
    removed = 0
    for folder in (UPLOAD_DIR, JOB_DIR, GENERATED_DIR):
        for path in folder.iterdir():
            if not path.is_file():
                continue
            modified = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
            if modified < cutoff:
                path.unlink(missing_ok=True)
                removed += 1
    return removed
