from __future__ import annotations

import json

import httpx
import pytest

import app.dashscope_audio_service as audio_service


def test_generates_fun_music_and_qwen_narration_with_one_key(tmp_path, monkeypatch):
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path.endswith("/models/permissions"):
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "output": {
                        "permissions": [
                            {
                                "model": "fun-music-v1",
                                "permissions": {"inference": True},
                            }
                        ]
                    },
                },
            )
        if request.url.path.endswith("/audio/music/generation"):
            return httpx.Response(
                200,
                json={"output": {"audio": {"url": "https://download.test/music.mp3"}}},
            )
        if request.url.path.endswith("/audio/tts/SpeechSynthesizer"):
            return httpx.Response(
                200,
                json={"output": {"audio": {"url": "https://download.test/speech.mp3"}}},
            )
        if request.url.host == "download.test":
            return httpx.Response(200, content=b"audio")
        return httpx.Response(404, json={"message": "not found"})

    monkeypatch.setenv("DASHSCOPE_API_KEY", "dashscope-test-key")
    monkeypatch.delenv("DASHSCOPE_WORKSPACE_ID", raising=False)
    monkeypatch.setattr(
        audio_service,
        "_client",
        lambda _timeout: httpx.Client(transport=httpx.MockTransport(handler)),
    )
    music = tmp_path / "music.mp3"
    speech = tmp_path / "speech.mp3"

    audio_service.generate_music("自然纯音乐", music)
    audio_service.generate_narration("听听周围的声音。", speech)

    assert music.read_bytes() == b"audio"
    assert speech.read_bytes() == b"audio"
    provider_requests = [
        request for request in requests if request.url.host != "download.test"
    ]
    assert all(
        request.headers["authorization"] == "Bearer dashscope-test-key"
        for request in provider_requests
    )
    music_request = next(
        request
        for request in requests
        if request.url.path.endswith("/audio/music/generation")
    )
    speech_request = next(
        request
        for request in requests
        if request.url.path.endswith("/audio/tts/SpeechSynthesizer")
    )
    music_body = json.loads(music_request.content)
    speech_body = json.loads(speech_request.content)
    assert music_body["model"] == "fun-music-v1"
    assert music_body["input"]["is_instrumental"] is True
    assert speech_body["model"] == "qwen-audio-3.0-tts-plus"
    assert speech_body["input"]["voice"] == "longanlingxin"


def test_skips_fun_music_when_inference_permission_is_denied(tmp_path, monkeypatch):
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path.endswith("/models/permissions"):
            return httpx.Response(
                200,
                json={
                    "success": True,
                    "output": {
                        "permissions": [
                            {
                                "model": "fun-music-v1",
                                "permissions": {"inference": False},
                            }
                        ]
                    },
                },
            )
        return httpx.Response(500, json={"message": "generation must be skipped"})

    monkeypatch.setenv("DASHSCOPE_API_KEY", "dashscope-test-key")
    monkeypatch.setattr(
        audio_service,
        "_client",
        lambda _timeout: httpx.Client(transport=httpx.MockTransport(handler)),
    )

    destination = tmp_path / "music.mp3"
    with pytest.raises(audio_service.MusicPermissionDenied, match="邀测权限"):
        audio_service.generate_music("自然纯音乐", destination)

    assert not destination.exists()
    assert [request.url.path for request in requests] == [
        "/api/v1/models/permissions"
    ]


def test_workspace_id_selects_beijing_dedicated_endpoint(monkeypatch):
    monkeypatch.setenv("DASHSCOPE_WORKSPACE_ID", "workspace-123")
    monkeypatch.delenv("DASHSCOPE_AIGC_BASE_URL", raising=False)

    assert (
        audio_service._api_base()
        == "https://workspace-123.cn-beijing.maas.aliyuncs.com/api/v1"
    )
