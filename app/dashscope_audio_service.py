from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any

import httpx

from app.observability import get_logger, log_event, log_exception


logger = get_logger("dashscope_audio")
FUN_MUSIC_APPLICATION_URL = "https://bailian.console.aliyun.com/cn-beijing/?tab=model"
FUN_MUSIC_PERMISSION_DENIED_MESSAGE = (
    "当前 API Key 未获得 Fun-Music 邀测权限，本次已跳过音乐生成。"
    "请前往阿里云百炼模型广场申请开通："
    f"{FUN_MUSIC_APPLICATION_URL}"
)


class MusicPermissionDenied(RuntimeError):
    pass


def _api_key() -> str:
    value = os.getenv("DASHSCOPE_API_KEY", "").strip()
    if not value:
        raise RuntimeError("缺少 DASHSCOPE_API_KEY")
    return value


def _api_base() -> str:
    configured = os.getenv("DASHSCOPE_AIGC_BASE_URL", "").rstrip("/")
    if configured:
        return configured
    workspace = os.getenv("DASHSCOPE_WORKSPACE_ID", "").strip()
    if workspace:
        return f"https://{workspace}.cn-beijing.maas.aliyuncs.com/api/v1"
    compatible = os.getenv(
        "DASHSCOPE_BASE_URL",
        "https://dashscope.aliyuncs.com/compatible-mode/v1",
    )
    return compatible.replace("/compatible-mode/v1", "/api/v1").rstrip("/")


def _payload(response: httpx.Response, service: str) -> dict[str, Any]:
    try:
        value = response.json()
    except ValueError as exc:
        raise RuntimeError(f"{service}返回了无法识别的数据") from exc
    if response.is_error:
        message = value.get("message") if isinstance(value, dict) else None
        raise RuntimeError(message or f"{service}调用失败：HTTP {response.status_code}")
    if not isinstance(value, dict):
        raise RuntimeError(f"{service}返回了无法识别的数据")
    return value


def _download(client: httpx.Client, url: str, destination: Path) -> None:
    with client.stream("GET", url) as response:
        response.raise_for_status()
        with destination.open("wb") as handle:
            for chunk in response.iter_bytes():
                handle.write(chunk)
    if not destination.exists() or destination.stat().st_size == 0:
        raise RuntimeError("百炼生成的音频文件为空")


def _client(timeout_seconds: float) -> httpx.Client:
    return httpx.Client(
        timeout=httpx.Timeout(timeout_seconds, connect=30),
        transport=httpx.HTTPTransport(retries=3),
    )


def _music_permission(
    client: httpx.Client,
    *,
    api_key: str,
    model: str,
) -> bool | None:
    started = time.perf_counter()
    try:
        response = client.get(
            f"{_api_base()}/models/permissions",
            headers={"Authorization": f"Bearer {api_key}"},
            params={"model": model},
        )
        if response.is_error:
            log_event(
                logger,
                logging.WARNING,
                "music_permission_check_unavailable",
                model=model,
                status_code=response.status_code,
                duration_ms=round((time.perf_counter() - started) * 1000),
            )
            return None
        payload = _payload(response, "百炼模型权限")
        output = payload.get("output") or {}
        entries = output.get("permissions") if isinstance(output, dict) else []
        matched = next(
            (
                item
                for item in entries or []
                if isinstance(item, dict) and str(item.get("model") or "") == model
            ),
            None,
        )
        permissions = matched.get("permissions") if isinstance(matched, dict) else {}
        allowed = bool(
            isinstance(permissions, dict) and permissions.get("inference") is True
        )
        log_event(
            logger,
            logging.INFO,
            "music_permission_checked",
            model=model,
            allowed=allowed,
            duration_ms=round((time.perf_counter() - started) * 1000),
        )
        return allowed
    except Exception as exc:
        log_exception(
            logger,
            "music_permission_check_unavailable",
            model=model,
            error_type=type(exc).__name__,
            duration_ms=round((time.perf_counter() - started) * 1000),
        )
        return None


def generate_music(prompt: str, destination: Path) -> None:
    model = os.getenv("DASHSCOPE_MUSIC_MODEL", "fun-music-v1")
    started = time.perf_counter()
    try:
        with _client(300) as client:
            api_key = _api_key()
            permission = _music_permission(
                client,
                api_key=api_key,
                model=model,
            )
            if permission is False:
                raise MusicPermissionDenied(FUN_MUSIC_PERMISSION_DENIED_MESSAGE)
            log_event(
                logger,
                logging.INFO,
                "music_request_started",
                model=model,
                input_chars=len(prompt),
                permission_checked=permission is not None,
            )
            response = client.post(
                f"{_api_base()}/services/audio/music/generation",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "input": {
                        "prompt": prompt,
                        "is_instrumental": True,
                        "format": "mp3",
                        "enable_aigc_watermark": False,
                    },
                },
            )
            payload = _payload(response, "阿里云 Fun-Music")
            url = str(((payload.get("output") or {}).get("audio") or {}).get("url") or "")
            if not url:
                raise RuntimeError("阿里云 Fun-Music 没有返回音乐文件")
            _download(client, url, destination)
        log_event(
            logger,
            logging.INFO,
            "music_request_completed",
            model=model,
            duration_ms=round((time.perf_counter() - started) * 1000),
            output_bytes=destination.stat().st_size,
        )
    except MusicPermissionDenied:
        log_event(
            logger,
            logging.WARNING,
            "music_request_skipped",
            model=model,
            reason="model_permission_denied",
            duration_ms=round((time.perf_counter() - started) * 1000),
        )
        raise
    except Exception:
        log_exception(
            logger,
            "music_request_failed",
            model=model,
            duration_ms=round((time.perf_counter() - started) * 1000),
        )
        raise


def generate_narration(text: str, destination: Path) -> None:
    model = os.getenv("DASHSCOPE_SPEECH_MODEL", "qwen-audio-3.0-tts-plus")
    voice = os.getenv("DASHSCOPE_SPEECH_VOICE", "longanlingxin")
    started = time.perf_counter()
    log_event(
        logger,
        logging.INFO,
        "speech_request_started",
        model=model,
        input_chars=len(text),
    )
    try:
        with _client(90) as client:
            response = client.post(
                f"{_api_base()}/services/audio/tts/SpeechSynthesizer",
                headers={
                    "Authorization": f"Bearer {_api_key()}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "input": {
                        "text": text,
                        "voice": voice,
                        "format": "mp3",
                        "sample_rate": 24000,
                        "instruction": "温暖、平静、有好奇心，像自然教育老师，语速稍慢，不夸张。",
                        "enable_aigc_tag": True,
                    },
                },
            )
            payload = _payload(response, "阿里云 Qwen-Audio-TTS")
            url = str(((payload.get("output") or {}).get("audio") or {}).get("url") or "")
            if not url:
                raise RuntimeError("阿里云 Qwen-Audio-TTS 没有返回旁白文件")
            _download(client, url, destination)
        log_event(
            logger,
            logging.INFO,
            "speech_request_completed",
            model=model,
            duration_ms=round((time.perf_counter() - started) * 1000),
            output_bytes=destination.stat().st_size,
        )
    except Exception:
        log_exception(
            logger,
            "speech_request_failed",
            model=model,
            duration_ms=round((time.perf_counter() - started) * 1000),
        )
        raise
