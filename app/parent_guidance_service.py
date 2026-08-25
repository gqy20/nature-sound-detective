from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import httpx
from dotenv import load_dotenv

from app.config import ROOT
from app.observability import get_logger, log_exception


logger = get_logger("parent_guidance")


ALLOWED_BEHAVIORS = {
    "recordedSound": "完成了一次声音记录",
    "replayedAudio": "主动回听了原声",
    "completedObservation": "完成了现场观察",
    "comparedEvidence": "比较了两类以上证据",
    "acceptedUncertainty": "愿意保留不确定",
    "retriedRecording": "录音失败后重新尝试",
    "observedSafely": "完成了明确记录的安全观察任务",
}
UNSAFE_PATTERN = re.compile(r"追逐|捕捉|抓住|触摸|投喂|拨开|翻开|爬树|下水|靠近巢穴")
FALSE_CONFIRMATION_PATTERN = re.compile(r"一定是|已经确认|确定就是|百分之百")
EMPTY_PRAISE_PATTERN = re.compile(r"你真棒|太聪明|小天才|最厉害")


def _parse_json(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
        if not match:
            raise ValueError("家长陪伴模型没有返回JSON")
        value = json.loads(match.group(0))
    if not isinstance(value, dict):
        raise ValueError("家长陪伴模型返回格式无效")
    return value


def _text(value: Any, *, minimum: int, maximum: int, field: str) -> str:
    result = str(value or "").strip()
    if not minimum <= len(result) <= maximum:
        raise ValueError(f"{field}长度无效")
    if UNSAFE_PATTERN.search(result) and not re.search(r"不要|避免|请勿|不能", result):
        raise ValueError(f"{field}包含不安全行为")
    if FALSE_CONFIRMATION_PATTERN.search(result):
        raise ValueError(f"{field}把候选写成了确认结果")
    return result


def validate_parent_guidance(
    raw: dict[str, Any], *, behaviors: list[str]
) -> dict[str, list[dict[str, str]]]:
    raw_guides = raw.get("guides")
    raw_praises = raw.get("praises")
    if not isinstance(raw_guides, list) or not 2 <= len(raw_guides) <= 3:
        raise ValueError("AI必须返回2至3条家长引导")
    if not isinstance(raw_praises, list) or not 3 <= len(raw_praises) <= 5:
        raise ValueError("AI必须返回3至5句过程性夸奖")
    allowed = set(behaviors) & ALLOWED_BEHAVIORS.keys()
    if not allowed:
        raise ValueError("没有可用于夸奖的真实行为")
    guides = []
    for item in raw_guides:
        if not isinstance(item, dict):
            raise ValueError("家长引导格式无效")
        guides.append(
            {
                "goal": _text(item.get("goal"), minimum=2, maximum=24, field="引导目标"),
                "say": _text(item.get("say"), minimum=6, maximum=90, field="家长说法"),
                "action": _text(item.get("action"), minimum=6, maximum=110, field="共同动作"),
                "avoid": _text(item.get("avoid"), minimum=4, maximum=90, field="避免事项"),
            }
        )
    praises = []
    for item in raw_praises:
        if not isinstance(item, dict):
            raise ValueError("过程性夸奖格式无效")
        behavior = str(item.get("evidence_behavior") or "").strip()
        if behavior not in allowed:
            raise ValueError("AI夸奖引用了没有发生的行为")
        text = _text(item.get("text"), minimum=8, maximum=90, field="夸奖文本")
        if EMPTY_PRAISE_PATTERN.search(text):
            raise ValueError("AI返回了没有具体证据的空泛夸奖")
        praises.append(
            {
                "evidence_behavior": behavior,
                "ability": _text(item.get("ability"), minimum=2, maximum=18, field="能力标签"),
                "text": text,
            }
        )
    return {"guides": guides, "praises": praises}


def _fallback(behaviors: list[str]) -> dict[str, list[dict[str, str]]]:
    available = [item for item in behaviors if item in ALLOWED_BEHAVIORS]
    if not available:
        available = ["recordedSound"]
    praise_templates = {
        "recordedSound": ("主动发现", "你把听到的声音认真记录下来，让这次好奇有了可以继续寻找的线索。"),
        "replayedAudio": ("认真求证", "你没有急着选答案，而是重新听了一遍，这是一种很认真的调查方法。"),
        "completedObservation": ("现场观察", "你不只看了候选，还回到现场寻找线索，观察得很完整。"),
        "comparedEvidence": ("比较证据", "你把声音和周围环境放在一起比较，已经在用证据作判断了。"),
        "acceptedUncertainty": ("诚实判断", "你愿意说暂时不知道，说明你很认真地对待证据。"),
        "retriedRecording": ("调整方法", "这次没有录清楚，但你愿意换个方法再试，调查正在进步。"),
        "observedSafely": ("尊重自然", "你留在安全区域安静观察，这是尊重自然的调查方式。"),
    }
    praises = []
    while len(praises) < 3:
        behavior = available[len(praises) % len(available)]
        ability, text = praise_templates[behavior]
        occurrence = sum(
            item["evidence_behavior"] == behavior for item in praises
        )
        if occurrence == 1:
            ability = "继续探索"
            text = (
                f"我注意到你{ALLOWED_BEHAVIORS[behavior]}，"
                "这让我们知道下一步还可以继续寻找什么。"
            )
        elif occurrence >= 2:
            ability = "留下证据"
            text = (
                f"刚才你{ALLOWED_BEHAVIORS[behavior]}，"
                "这是这次调查中一条属于你自己的真实证据。"
            )
        praises.append(
            {"evidence_behavior": behavior, "ability": ability, "text": text}
        )
    return {
        "guides": [
            {
                "goal": "让孩子先描述声音",
                "say": "先不看候选，你觉得它是连续的，还是叫几声会停下来？",
                "action": "一起回听关键声段，请孩子用手轻轻打出节奏。",
                "avoid": "不要先说物种名称，也不要提示正确答案。",
            },
            {
                "goal": "寻找环境证据",
                "say": "你看高处，我看低处，等一会儿我们交换各自发现。",
                "action": "站在公开步道上观察树冠、灌木、水边和地面。",
                "avoid": "不要追逐声源、拨开灌木或靠近巢穴和水边。",
            },
            {
                "goal": "保留合理的不确定",
                "say": "你现在是比较确定、有一个猜想，还是还需要更多证据？",
                "action": "允许孩子选择暂时不知道，并说出下一次想验证什么。",
                "avoid": "不要要求孩子必须从候选中选出一个。",
            },
        ],
        "praises": praises,
    }


def _prompt(
    *,
    candidate_name: str,
    category: str,
    confidence: float,
    weak_signal: bool,
    observations: list[str],
    behaviors: list[str],
) -> str:
    behavior_lines = [
        f"- {item}: {ALLOWED_BEHAVIORS[item]}"
        for item in behaviors
        if item in ALLOWED_BEHAVIORS
    ]
    return f"""请直接为一位正在陪孩子进行自然声音调查的家长生成现场引导和过程性夸奖。

候选：{candidate_name or '暂时没有具体候选'}
声音类别：{category or '自然声音'}
模型分数：{confidence:.2f}，这不是准确率
录音是否为弱动态信号：{'是' if weak_signal else '否'}
孩子/家庭实际填写的观察：{'、'.join(observations) or '暂无'}
本次真实发生的行为：
{chr(10).join(behavior_lines)}

你必须直接创作自然、具体、不重复的中文表达。每句夸奖必须严格依据上面的真实行为，并在evidence_behavior中逐字返回对应ID。不得虚构孩子看见动物、留在步道、认真比较、重新录音等没有列出的行为。不得把候选写成确定答案。引导只能鼓励远距离倾听和观看，不得鼓励追逐、捕捉、触摸、投喂、拨开灌木、爬树、下水或靠近巢穴。避免“你真棒、太聪明、小天才”等空泛评价。

返回JSON，不要Markdown：
{{"guides":[{{"goal":"目标","say":"家长可以直接说的话","action":"一起做的动作","avoid":"需要避免的做法"}}],"praises":[{{"evidence_behavior":"真实行为ID","ability":"能力标签","text":"家长可以直接说的具体夸奖"}}]}}
guides必须2至3条，praises必须3至5条。"""


class ParentGuidanceService:
    def __init__(self) -> None:
        load_dotenv(ROOT / ".env")
        self.mode = os.getenv("PARENT_GUIDANCE_MODE", "live").strip().lower()
        self.model = os.getenv(
            "PARENT_GUIDANCE_MODEL",
            os.getenv("STORY_MODEL", "qwen3.7-flash"),
        ).strip()
        self.api_key = os.getenv(
            "PARENT_GUIDANCE_API_KEY",
            os.getenv("STORY_API_KEY", os.getenv("DASHSCOPE_API_KEY", "")),
        ).strip()
        self.api_base = os.getenv(
            "PARENT_GUIDANCE_API_BASE",
            os.getenv(
                "STORY_API_BASE",
                os.getenv(
                    "DASHSCOPE_BASE_URL",
                    "https://dashscope.aliyuncs.com/compatible-mode/v1",
                ),
            ),
        ).rstrip("/")

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        behaviors = [
            str(item) for item in payload.get("behaviors") or []
            if str(item) in ALLOWED_BEHAVIORS
        ]
        fallback = _fallback(behaviors)
        if self.mode != "live" or not self.api_key:
            return {
                **fallback,
                "provider": "reviewed-template",
                "ai_generated": False,
                "warning": "AI陪伴模型未启用，已使用审核模板",
                "diagnostic_code": "not_configured",
            }
        try:
            with httpx.Client(timeout=httpx.Timeout(35, connect=12)) as client:
                response = client.post(
                    f"{self.api_base}/chat/completions",
                    headers={
                        "Authorization": f"Bearer {self.api_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": self.model,
                        "messages": [
                            {
                                "role": "system",
                                "content": "你是亲子自然教育陪伴编辑。真实行为证据、安全和儿童自主性高于文采。",
                            },
                            {
                                "role": "user",
                                "content": _prompt(
                                    candidate_name=str(payload.get("candidate_name") or ""),
                                    category=str(payload.get("category") or ""),
                                    confidence=float(payload.get("confidence") or 0),
                                    weak_signal=bool(payload.get("weak_signal", False)),
                                    observations=[str(item) for item in payload.get("observations") or []],
                                    behaviors=behaviors,
                                ),
                            },
                        ],
                        "temperature": 0.85,
                        "enable_thinking": False,
                        "max_completion_tokens": 900,
                        "response_format": {"type": "json_object"},
                    },
                )
                response.raise_for_status()
                raw = _parse_json(response.json()["choices"][0]["message"]["content"])
                result = validate_parent_guidance(raw, behaviors=behaviors)
                return {
                    **result,
                    "provider": self.model,
                    "ai_generated": True,
                    "warning": "",
                }
        except Exception as exc:
            log_exception(
                logger,
                "parent_guidance_fallback_used",
                provider=self.model,
                error_type=type(exc).__name__,
            )
            return {
                **fallback,
                "provider": "reviewed-template",
                "ai_generated": False,
                "warning": "AI生成未通过事实或安全校验，已使用审核模板",
                "diagnostic_code": type(exc).__name__,
                "diagnostic_detail": str(exc)[:160],
            }
