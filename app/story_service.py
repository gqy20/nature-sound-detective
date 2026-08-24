from __future__ import annotations

import json
import logging
import os
import re
import time
from datetime import datetime, timezone
from typing import Any

import httpx
from dotenv import load_dotenv

from app.config import ROOT
from app.observability import get_logger, log_event, log_exception


logger = get_logger("story")

ANIMAL_CATEGORIES = {"鸟类鸣叫", "蛙类鸣叫", "昆虫鸣叫"}
STORY_TYPES = {"animal_life", "why_it_calls"}
DANGEROUS_PATTERN = re.compile(r"追逐|捕捉|抓住|触摸|投喂|拨开|翻开|爬树|下水|靠近巢穴")
SAFETY_NEGATION_PATTERN = re.compile(r"不要|不应|请勿|避免|不能|不可")
USER_DANGEROUS_PATTERN = re.compile(
    r"(?:(?:孩子|小朋友|你|我们).{0,6}(?:可以|应该|不妨|试着|一起|去|来)|(?:邀请|鼓励|让)(?:孩子|小朋友)).{0,12}(?:追逐|捕捉|抓住|触摸|投喂|拨开|翻开|爬树|下水|靠近巢穴)"
)
IMPERATIVE_DANGEROUS_PATTERN = re.compile(
    r"(?:请|可以|应该|建议|不妨|试着|一起|去|来).{0,16}(?:追逐|捕捉|抓住|触摸|投喂|拨开|翻开)"
)
ALWAYS_UNSAFE_OBSERVATION_PATTERN = re.compile(r"爬树|下水|靠近巢穴")
FALSE_CONFIRMATION_PATTERN = re.compile(r"这段录音(?:中|里)?(?:就是|确定是)|我们(?:已经)?确认|一定是|发现了一只")
PRECISE_NUMBER_PATTERN = re.compile(r"\d+(?:\.\d+)?\s*(?:年|个月|枚|只|公里|千米|米)")
UNVERIFIED_CLAIM_PATTERN = re.compile(r"生态(?:健康)?指标|环境健康指标|不挖洞|从不|绝不")


def story_candidates(result: dict[str, Any]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    seen: set[str] = set()
    for detection in result.get("detections") or []:
        if not isinstance(detection, dict):
            continue
        species = detection.get("specific_species")
        if not isinstance(species, dict) or not species.get("name_zh"):
            continue
        candidate_id = str(
            species.get("taxonomy_id")
            or species.get("scientific_name")
            or species.get("name_zh")
        )
        if candidate_id in seen:
            continue
        seen.add(candidate_id)
        candidates.append(
            {
                "id": candidate_id,
                "name_zh": str(species["name_zh"]),
                "scientific_name": species.get("scientific_name"),
                "category": detection.get("name_zh") or result.get("primary_sound_type"),
                "candidate_status": "candidate",
            }
        )
    if candidates:
        return candidates[:3]
    primary = str(result.get("primary_sound_type") or "")
    if primary not in ANIMAL_CATEGORIES:
        return []
    group = {
        "鸟类鸣叫": ("bird", "鸟类"),
        "蛙类鸣叫": ("frog", "蛙类"),
        "昆虫鸣叫": ("insect", "鸣虫"),
    }[primary]
    return [
        {
            "id": f"category:{group[0]}",
            "name_zh": group[1],
            "scientific_name": None,
            "category": primary,
            "candidate_status": "category_only",
        }
    ]


def find_story_candidate(result: dict[str, Any], candidate_id: str) -> dict[str, Any]:
    for candidate in story_candidates(result):
        if candidate["id"] == candidate_id:
            return candidate
    raise ValueError("故事候选不在本次声音分析结果中")


def _parse_json(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
        if not match:
            raise ValueError("故事模型没有返回JSON")
        value = json.loads(match.group(0))
    if not isinstance(value, dict):
        raise ValueError("故事模型返回格式无效")
    return value


def _validate_story(raw: dict[str, Any], candidate: dict[str, Any]) -> dict[str, str]:
    title = str(raw.get("title") or "").strip()
    story = str(raw.get("story") or "").strip()
    observation = str(raw.get("observation_prompt") or "").strip()
    if not 4 <= len(title) <= 28:
        raise ValueError("动物故事标题长度无效")
    if not 80 <= len(story) <= 360:
        raise ValueError("动物故事正文长度无效")
    if not 8 <= len(observation) <= 100:
        raise ValueError("动物故事观察问题长度无效")
    combined = f"{title}\n{story}\n{observation}"
    safety_scan = "".join(
        segment
        for segment in re.split(r"[。！？；\n]", f"{story}\n{observation}")
        if not (SAFETY_NEGATION_PATTERN.search(segment) and DANGEROUS_PATTERN.search(segment))
    )
    observation_scan = "".join(
        segment
        for segment in re.split(r"[。！？；\n]", observation)
        if not (SAFETY_NEGATION_PATTERN.search(segment) and DANGEROUS_PATTERN.search(segment))
    )
    if (
        ALWAYS_UNSAFE_OBSERVATION_PATTERN.search(observation_scan)
        or IMPERATIVE_DANGEROUS_PATTERN.search(observation_scan)
        or USER_DANGEROUS_PATTERN.search(safety_scan)
    ):
        raise ValueError("动物故事包含不安全观察行为")
    if FALSE_CONFIRMATION_PATTERN.search(combined):
        raise ValueError("动物故事把候选写成了确认结果")
    if PRECISE_NUMBER_PATTERN.search(story):
        raise ValueError("无知识库模式不允许生成未经核验的精确数字")
    if UNVERIFIED_CLAIM_PATTERN.search(story):
        raise ValueError("无知识库模式不允许生成高风险或绝对物种断言")
    if candidate["name_zh"] not in combined:
        raise ValueError("动物故事没有围绕所选候选")
    return {"title": title, "story": story, "observation_prompt": observation}


def _template_story(candidate: dict[str, Any], story_type: str) -> dict[str, str]:
    name = candidate["name_zh"]
    category = candidate["category"]
    if story_type == "why_it_calls":
        story = (
            f"今天先来认识候选动物{name}。动物发出声音，常常与联系同伴、表达位置或适应周围环境有关。"
            f"{name}的真实叫声会受到时间、距离和环境噪声影响，所以一次录音只能提供{category}线索。"
            "把声音的节奏、方向和出现时间记下来，下一次再比较，才能逐渐接近答案。"
        )
        observation = f"下一次听到相似声音时，可以远远记录{name}候选声音的节奏是否重复。"
        title = f"{name}为什么发声"
    else:
        story = (
            f"今天先来认识候选动物{name}。每种动物都有自己的活动时间、寻找食物的方法和与同伴联系的方式。"
            f"声音是认识{name}的一条线索，但真实生活还藏在它活动的高度、周围环境和声音节奏里。"
            "我们不急着宣布答案，而是把这些特点逐次记录，让下一次观察补上新的证据。"
        )
        observation = f"下一次可以远远观察，{name}候选声音来自高处、低处还是地面附近。"
        title = f"认识候选动物{name}"
    return {"title": title[:28], "story": story, "observation_prompt": observation}


def _prompt(candidate: dict[str, Any], location: str, story_type: str) -> str:
    angle = "它为什么发声" if story_type == "why_it_calls" else "这个动物怎样度过一天"
    return f"""请为6至12岁儿童创作一则关于候选动物的中文科普故事。
候选动物：{candidate['name_zh']}
学名：{candidate.get('scientific_name') or '未提供'}
候选层级：{candidate['candidate_status']}
声音大类：{candidate['category']}
区域背景：{location or '杭州'}，仅表示项目服务区域，不得虚构西湖、植物园、公园、池塘、芦苇荡等具体采集地点
故事主题：{angle}

当前没有外部物种知识库。只使用广泛、稳妥的常识，不写精确寿命、数量、距离、保护等级、繁殖数字、生态健康指标、绝对习性或未经核验的独特结论。不要使用“从不”“绝不”“不挖洞”等绝对句式。故事主体必须是动物本身，而不是录音现场或孩子的调查过程。不得声称本次录音已经确认这个动物，不得鼓励追逐、捕捉、触摸、投喂、爬树或靠近巢穴。动物自身捕食昆虫等自然行为可以描述，但观察建议只能是远距离倾听和观看。

返回JSON，不要Markdown：
{{"title":"4至28字","story":"120至260字，介绍动物生活或发声，语言生动但不虚构精确事实","observation_prompt":"一句安全、远距离、可执行的观察建议"}}"""


class AnimalStoryService:
    def __init__(self) -> None:
        load_dotenv(ROOT / ".env")
        self.mode = os.getenv("STORY_MODE", "template").strip().lower()
        self.model = os.getenv("STORY_MODEL", "qwen3.7-flash").strip()
        self.api_key = os.getenv("STORY_API_KEY", os.getenv("DASHSCOPE_API_KEY", "")).strip()
        self.api_base = os.getenv(
            "STORY_API_BASE",
            os.getenv("DASHSCOPE_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        ).rstrip("/")

    def create(
        self,
        *,
        result: dict[str, Any],
        candidate_id: str,
        location: str,
        story_type: str = "animal_life",
    ) -> dict[str, Any]:
        if story_type not in STORY_TYPES:
            raise ValueError("暂不支持这种动物故事类型")
        candidate = find_story_candidate(result, candidate_id)
        started = time.perf_counter()
        warning = ""
        provider = "reviewed-template"
        usage = None
        story = _template_story(candidate, story_type)
        if self.mode == "live":
            if not self.api_key:
                warning = "故事模型未配置，已使用安全模板"
            else:
                try:
                    with httpx.Client(timeout=httpx.Timeout(45, connect=15)) as client:
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
                                        "content": "你是儿童自然教育故事编辑。事实边界、安全和候选状态高于故事性。",
                                    },
                                    {"role": "user", "content": _prompt(candidate, location, story_type)},
                                ],
                                "temperature": 0.7,
                                "enable_thinking": False,
                                "max_completion_tokens": 500,
                                "response_format": {"type": "json_object"},
                            },
                        )
                        response.raise_for_status()
                        payload = response.json()
                        raw = _parse_json(payload["choices"][0]["message"]["content"])
                        story = _validate_story(raw, candidate)
                        usage = payload.get("usage")
                        provider = self.model
                except Exception as exc:
                    warning = "模型故事未通过生成或安全校验，已使用安全模板"
                    log_exception(logger, "animal_story_fallback_used", error_type=type(exc).__name__)
        created = {
            "status": "completed",
            "candidate": candidate,
            "story_type": story_type,
            **story,
            "candidate_notice": f"这是关于候选动物{candidate['name_zh']}的AI故事，不代表本次录音已经确认物种。",
            "content_label": "AI基于候选信息创作" if provider != "reviewed-template" else "安全模板故事",
            "provider": provider,
            "model": self.model if provider != "reviewed-template" else None,
            "warning": warning,
            "usage": usage,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "duration_ms": round((time.perf_counter() - started) * 1000),
        }
        log_event(
            logger,
            logging.INFO,
            "animal_story_completed",
            candidate_id=candidate["id"],
            provider=provider,
            duration_ms=created["duration_ms"],
        )
        return created
