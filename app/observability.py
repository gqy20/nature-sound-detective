from __future__ import annotations

import json
import logging
import os
import re
import sys
import time
import traceback
from contextlib import contextmanager
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any, Iterator
from uuid import uuid4

from fastapi import FastAPI, Request


TRACE_HEADER = "X-Trace-ID"
_trace_id: ContextVar[str] = ContextVar("trace_id", default="system")
_trace_pattern = re.compile(r"^[A-Za-z0-9_.-]{8,80}$")
_sensitive_parts = ("api_key", "apikey", "authorization", "token", "audio_path", "prompt", "response_body")


def current_trace_id() -> str:
    return _trace_id.get()


def normalize_trace_id(value: str | None) -> str:
    candidate = (value or "").strip()
    return candidate if _trace_pattern.fullmatch(candidate) else f"trace_{uuid4().hex}"


@contextmanager
def trace_context(trace_id: str) -> Iterator[None]:
    token = _trace_id.set(normalize_trace_id(trace_id))
    try:
        yield
    finally:
        _trace_id.reset(token)


def _safe_value(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float)):
        return value
    text = str(value)[:500]
    text = re.sub(r"(?i)bearer\s+[a-z0-9._-]+", "Bearer [REDACTED]", text)
    return re.sub(r"(?i)sk-[a-z0-9_-]{8,}", "[REDACTED_KEY]", text)


def _safe_fields(fields: dict[str, Any]) -> dict[str, Any]:
    return {
        key: "[REDACTED]" if any(part in key.lower() for part in _sensitive_parts) else _safe_value(value)
        for key, value in fields.items()
    }


class JsonLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname.lower(),
            "component": record.name,
            "event": getattr(record, "event_name", record.getMessage()),
            "trace_id": current_trace_id(),
        }
        payload.update(getattr(record, "event_fields", {}))
        if record.exc_info:
            payload["exception_type"] = record.exc_info[0].__name__
            payload["stack_trace"] = "".join(traceback.format_tb(record.exc_info[2]))[-4000:]
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def configure_logging() -> None:
    root = logging.getLogger("xykw")
    if any(getattr(handler, "xykw_json", False) for handler in root.handlers):
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonLogFormatter())
    handler.xykw_json = True  # type: ignore[attr-defined]
    root.addHandler(handler)
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    root.propagate = False


def get_logger(component: str) -> logging.Logger:
    configure_logging()
    return logging.getLogger(f"xykw.{component}")


def log_event(logger: logging.Logger, level: int, event: str, **fields: Any) -> None:
    logger.log(level, event, extra={"event_name": event, "event_fields": _safe_fields(fields)})


def log_exception(logger: logging.Logger, event: str, **fields: Any) -> None:
    logger.error(
        event,
        exc_info=True,
        extra={"event_name": event, "event_fields": _safe_fields(fields)},
    )


def install_observability(app: FastAPI, component: str) -> None:
    logger = get_logger(component)

    @app.middleware("http")
    async def observe_request(request: Request, call_next):
        trace_id = normalize_trace_id(request.headers.get(TRACE_HEADER))
        token = _trace_id.set(trace_id)
        started = time.perf_counter()
        try:
            response = await call_next(request)
            duration_ms = round((time.perf_counter() - started) * 1000)
            log_event(
                logger,
                logging.WARNING if response.status_code >= 500 else logging.INFO,
                "http_request_completed",
                method=request.method,
                route=request.url.path,
                status_code=response.status_code,
                duration_ms=duration_ms,
            )
            response.headers[TRACE_HEADER] = trace_id
            return response
        except Exception:
            log_exception(
                logger,
                "http_request_failed",
                method=request.method,
                route=request.url.path,
                duration_ms=round((time.perf_counter() - started) * 1000),
            )
            raise
        finally:
            _trace_id.reset(token)
