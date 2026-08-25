import json

import httpx
import pytest

import app.parent_guidance_service as guidance_module
from app.parent_guidance_service import (
    ParentGuidanceService,
    validate_parent_guidance,
)


def _ai_payload():
    return {
        "guides": [
            {
                "goal": "听见节奏变化",
                "say": "你愿意再听一次，告诉我哪一声最特别吗？",
                "action": "一起回听关键声段，各自用手打出听见的节奏。",
                "avoid": "不要先告诉孩子候选名称。",
            },
            {
                "goal": "比较现场证据",
                "say": "声音和周围环境，哪一条线索最支持你的猜想？",
                "action": "各说一条支持和一条还不能确定的线索。",
                "avoid": "不要要求孩子必须选出答案。",
            },
        ],
        "praises": [
            {
                "evidence_behavior": "recordedSound",
                "ability": "主动记录",
                "text": "你把这段声音保存下来，让刚才的好奇变成了可以继续寻找的线索。",
            },
            {
                "evidence_behavior": "replayedAudio",
                "ability": "认真求证",
                "text": "你愿意重新听一遍再判断，说明你在认真核对自己的发现。",
            },
            {
                "evidence_behavior": "replayedAudio",
                "ability": "耐心倾听",
                "text": "第二次回听时你还在寻找细节，这份耐心让观察更可靠。",
            },
        ],
    }


def test_template_fallback_is_available_without_ai(monkeypatch):
    monkeypatch.setenv("PARENT_GUIDANCE_MODE", "template")
    result = ParentGuidanceService().create(
        {"behaviors": ["recordedSound", "replayedAudio"]}
    )
    assert result["ai_generated"] is False
    assert result["provider"] == "reviewed-template"
    assert len(result["guides"]) == 3
    assert len(result["praises"]) == 3
    assert len({item["text"] for item in result["praises"]}) == 3


def test_live_ai_directly_generates_guidance_and_praise(monkeypatch):
    monkeypatch.setenv("PARENT_GUIDANCE_MODE", "live")
    monkeypatch.setenv("PARENT_GUIDANCE_API_KEY", "test-key")
    monkeypatch.setenv("PARENT_GUIDANCE_MODEL", "qwen3.7-flash")

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["temperature"] == 0.85
        assert "recordedSound" in body["messages"][1]["content"]
        return httpx.Response(
            200,
            json={
                "choices": [
                    {"message": {"content": json.dumps(_ai_payload(), ensure_ascii=False)}}
                ]
            },
        )

    real_client = httpx.Client
    monkeypatch.setattr(
        guidance_module.httpx,
        "Client",
        lambda **_kwargs: real_client(transport=httpx.MockTransport(handler)),
    )
    result = ParentGuidanceService().create(
        {
            "candidate_name": "珠颈斑鸠",
            "category": "鸟类鸣叫",
            "confidence": 0.82,
            "observations": ["声音来自树冠"],
            "behaviors": ["recordedSound", "replayedAudio"],
        }
    )
    assert result["ai_generated"] is True
    assert result["provider"] == "qwen3.7-flash"
    assert result["praises"][0]["text"].startswith("你把这段声音")


def test_validation_rejects_praise_for_behavior_that_did_not_happen():
    payload = _ai_payload()
    payload["praises"][0]["evidence_behavior"] = "observedSafely"
    with pytest.raises(ValueError, match="没有发生"):
        validate_parent_guidance(
            payload,
            behaviors=["recordedSound", "replayedAudio"],
        )


def test_live_ai_retries_once_after_behavior_validation_failure(monkeypatch):
    monkeypatch.setenv("PARENT_GUIDANCE_MODE", "live")
    monkeypatch.setenv("PARENT_GUIDANCE_API_KEY", "test-key")
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        payload = _ai_payload()
        if calls == 1:
            payload["praises"][0]["evidence_behavior"] = "observedSafely"
        else:
            body = json.loads(request.content)
            assert "上一次输出已被拒绝" in body["messages"][1]["content"]
        return httpx.Response(
            200,
            json={
                "choices": [
                    {"message": {"content": json.dumps(payload, ensure_ascii=False)}}
                ]
            },
        )

    real_client = httpx.Client
    monkeypatch.setattr(
        guidance_module.httpx,
        "Client",
        lambda **_kwargs: real_client(transport=httpx.MockTransport(handler)),
    )
    result = ParentGuidanceService().create(
        {"behaviors": ["recordedSound", "replayedAudio"]}
    )

    assert calls == 2
    assert result["ai_generated"] is True
    assert result["generation_attempts"] == 2
