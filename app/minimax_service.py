from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from typing import Any

import httpx
import websockets


API_BASE = "https://api.minimaxi.com"


def _api_key() -> str:
    value = os.getenv("MINIMAX_API_KEY", "").strip()
    if not value:
        raise RuntimeError("缺少 MINIMAX_API_KEY")
    return value


def _check_response(payload: dict[str, Any], service: str) -> None:
    base = payload.get("base_resp") or {}
    code = base.get("status_code", 0)
    if code not in {0, None}:
        raise RuntimeError(f"{service}调用失败：{base.get('status_msg') or code}")


async def _speech_websocket(text: str, destination: Path) -> None:
    endpoint = os.getenv("MINIMAX_SPEECH_WS_URL", "wss://api.minimaxi.com/ws/v1/t2a_v2")
    headers = {"Authorization": f"Bearer {_api_key()}"}
    model = os.getenv("MINIMAX_SPEECH_MODEL", "speech-2.8-hd")
    voice = os.getenv("MINIMAX_SPEECH_VOICE", "female-tianmei")
    audio = bytearray()
    async with websockets.connect(
        endpoint, additional_headers=headers, open_timeout=30, close_timeout=10, max_size=8 * 1024 * 1024
    ) as websocket:
        connected = json.loads(await asyncio.wait_for(websocket.recv(), timeout=30))
        if connected.get("event") != "connected_success":
            raise RuntimeError(f"MiniMax 语音连接失败：{connected}")
        await websocket.send(json.dumps({
            "event": "task_start",
            "model": model,
            "voice_setting": {
                "voice_id": voice, "speed": 0.95, "vol": 1.0, "pitch": 0,
                "emotion": "calm", "english_normalization": False,
            },
            "audio_setting": {
                "sample_rate": 32000, "bitrate": 128000, "format": "mp3", "channel": 1,
            },
            "language_boost": "Chinese",
        }, ensure_ascii=False))
        started = json.loads(await asyncio.wait_for(websocket.recv(), timeout=30))
        if started.get("event") != "task_started":
            raise RuntimeError(f"MiniMax 语音任务启动失败：{started}")
        await websocket.send(json.dumps({"event": "task_continue", "text": text}, ensure_ascii=False))
        while True:
            message = json.loads(await asyncio.wait_for(websocket.recv(), timeout=90))
            chunk = (message.get("data") or {}).get("audio")
            if chunk:
                audio.extend(bytes.fromhex(chunk))
            if message.get("is_final"):
                _check_response(message, "MiniMax 语音")
                break
        await websocket.send(json.dumps({"event": "task_finish"}))
    if not audio:
        raise RuntimeError("MiniMax 语音没有返回音频")
    destination.write_bytes(audio)


def generate_narration(text: str, destination: Path) -> None:
    """Generate narration with the official MiniMax synchronous WebSocket API."""
    asyncio.run(_speech_websocket(text, destination))


def generate_music(prompt: str, destination: Path) -> None:
    """Generate instrumental background music and persist the expiring result locally."""
    model = os.getenv("MINIMAX_MUSIC_MODEL", "music-3.0")
    transport = httpx.HTTPTransport(retries=3)
    with httpx.Client(timeout=httpx.Timeout(300, connect=30), transport=transport) as client:
        response = client.post(
            f"{os.getenv('MINIMAX_API_BASE', API_BASE).rstrip('/')}/v1/music_generation",
            headers={"Authorization": f"Bearer {_api_key()}", "Content-Type": "application/json"},
            json={
                "model": model,
                "prompt": prompt,
                "is_instrumental": True,
                "stream": False,
                "output_format": "url",
                "aigc_watermark": True,
                "audio_setting": {"sample_rate": 44100, "bitrate": 256000, "format": "mp3"},
            },
        )
        if response.is_error:
            raise RuntimeError(f"MiniMax 音乐调用失败：{response.text[:800]}")
        payload = response.json()
        _check_response(payload, "MiniMax 音乐")
        value = (payload.get("data") or {}).get("audio")
        if not value:
            raise RuntimeError(f"MiniMax 音乐没有返回音频：{json.dumps(payload, ensure_ascii=False)[:500]}")
        if str(value).startswith(("http://", "https://")):
            with client.stream("GET", str(value)) as download:
                download.raise_for_status()
                with destination.open("wb") as handle:
                    for chunk in download.iter_bytes():
                        handle.write(chunk)
        else:
            destination.write_bytes(bytes.fromhex(str(value)))
