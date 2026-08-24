from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4


SENSITIVE_PARTS = (
    "api_key",
    "apikey",
    "authorization",
    "password",
    "secret",
    "access_token",
    "refresh_token",
    "read_write_token",
)


def _json_copy(value: Any) -> Any:
    return json.loads(json.dumps(value, ensure_ascii=False, default=str))


def sanitize(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: "[REDACTED]"
            if key.lower() == "token" or any(part in key.lower() for part in SENSITIVE_PARTS)
            else sanitize(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, str) and value.lower().startswith("bearer "):
        return "Bearer [REDACTED]"
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def create_run_id(label: str = "analysis") -> str:
    safe = "".join(character if character.isalnum() or character in "-_" else "-" for character in label)
    return f"{datetime.now().strftime('%Y%m%d-%H%M%S')}-{safe[:32]}-{uuid4().hex[:8]}"


def write_run_package(
    output_root: Path,
    *,
    run: dict[str, Any],
    result: dict[str, Any],
    investigation: dict[str, Any],
    progress: list[dict[str, Any]] | None = None,
) -> Path:
    run_dir = output_root / str(run["run_id"])
    run_dir.mkdir(parents=True, exist_ok=False)
    files = {
        "run.json": sanitize(_json_copy(run)),
        "result.json": sanitize(_json_copy(result)),
        "investigation.json": sanitize(_json_copy(investigation)),
        "progress.json": sanitize(_json_copy(progress or [])),
    }
    for name, payload in files.items():
        (run_dir / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return run_dir


def load_run_package(run_dir: Path) -> dict[str, Any]:
    if not run_dir.is_dir():
        raise FileNotFoundError(f"运行包不存在：{run_dir}")
    package: dict[str, Any] = {}
    for key, name in (
        ("run", "run.json"),
        ("result", "result.json"),
        ("investigation", "investigation.json"),
        ("progress", "progress.json"),
    ):
        path = run_dir / name
        if not path.is_file():
            raise FileNotFoundError(f"运行包缺少{name}")
        package[key] = json.loads(path.read_text(encoding="utf-8"))
    return package


def update_investigation(run_dir: Path, investigation: dict[str, Any]) -> None:
    (run_dir / "investigation.json").write_text(
        json.dumps(sanitize(_json_copy(investigation)), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def environment_flags() -> dict[str, bool]:
    return {
        "qwen_configured": bool(os.getenv("DASHSCOPE_API_KEY")),
        "minimax_configured": bool(os.getenv("MINIMAX_API_KEY")),
        "wan_live_enabled": os.getenv("WAN_VIDEO_MODE", "mock").strip().lower() == "live",
    }


def base_run_manifest(run_id: str, *, location: str, mode: str, source: Path) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "run_id": run_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "mode": mode,
        "location": location,
        "source": {
            "name": source.name,
            "size_bytes": source.stat().st_size,
            "sha256": sha256_file(source),
        },
        "environment": environment_flags(),
    }
