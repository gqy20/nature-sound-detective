from __future__ import annotations

import json
import hashlib
import logging
import os
import re
import secrets
import time
from datetime import datetime, timezone
from typing import Any

import httpx
from dotenv import load_dotenv

from app.config import ROOT
from app.generated_prompts import prompt_generation, prompt_version, render_prompt
from app.observability import get_logger, log_event, log_exception


logger = get_logger("story")
PROMPT_VERSION = prompt_version("story")
PROMPT_GENERATION = prompt_generation("story")

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
MARKDOWN_PATTERN = re.compile(r"(?:\*\*|__|```|^#{1,6}\s|^\s*[-*]\s)", re.MULTILINE)
UNSUPPORTED_DETAIL_PATTERN = re.compile(
    r"宣告领地|占领领地|求偶|标志性|露水|嫩叶|繁殖季|产卵|"
    r"寻找食物|觅食|同伴交流|城市邻居|水草间|湿润环境"
)
TIME_CONFLICTS = {
    "清晨": re.compile(r"傍晚|夜间|夜幕|夜色"),
    "白天": re.compile(r"清晨|早晨|傍晚|夜间|夜幕|夜色"),
    "傍晚": re.compile(r"清晨|早晨|白天"),
    "夜间": re.compile(r"清晨|早晨|白天|傍晚"),
}


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


def _validate_story(
    raw: dict[str, Any],
    candidate: dict[str, Any],
    observations: list[dict[str, Any]] | None = None,
) -> dict[str, str]:
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
    if MARKDOWN_PATTERN.search(combined):
        raise ValueError("动物故事不应包含Markdown标记")
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
    if UNSUPPORTED_DETAIL_PATTERN.search(story):
        raise ValueError("无知识库模式不允许生成未核验的生态细节")
    if candidate["name_zh"] not in combined:
        raise ValueError("动物故事没有围绕所选候选")
    expected_observations = {
        str(item.get("label")) for item in observations or [] if item.get("value") != "unknown"
    }
    claimed_observations = {
        str(value) for value in raw.get("observations_used") or []
    }
    if expected_observations and claimed_observations != expected_observations:
        raise ValueError("动物故事没有完整使用结构化现场观察")
    missing_observations = expected_observations.difference(
        label for label in expected_observations if label in story
    )
    if missing_observations:
        raise ValueError("动物故事没有在正文中使用全部现场观察")
    selected_times = {
        str(item.get("label"))
        for item in observations or []
        if item.get("dimension") == "time" and item.get("value") != "unknown"
    }
    for selected_time in selected_times:
        conflict = TIME_CONFLICTS.get(selected_time)
        if conflict and conflict.search(story):
            raise ValueError("动物故事与现场观察时间矛盾")
    return {"title": title, "story": story, "observation_prompt": observation}


def _template_story(candidate: dict[str, Any], story_type: str, observations: list[dict[str, Any]]) -> dict[str, str]:
    name = candidate["name_zh"]
    labels = [str(item.get("label")) for item in observations if item.get("value") != "unknown"]
    observed = "、".join(labels)
    subject = f"{name}候选者"
    variant = secrets.randbelow(3)
    if story_type == "why_it_calls":
        stories = [
            (
                f"故事里的{subject}没有露出全貌，只留下了{observed}这几条线索。"
                "声音一次次出现，又消失在周围的环境里。"
                f"它为什么发声，现在还不能下结论。对{name}的好奇，可以先放在下一次相遇里。"
                "多记一次方向和节奏，就会多一块接近答案的拼图。"
            ),
            (
                f"{name}候选者用{observed}开始了这个声音故事。"
                "我们听见了它，却还不知道这些声音真正想表达什么。"
                "未知没有让故事停下，反而让每一次重新倾听都变得重要。"
                f"只要继续在远处记录，{name}的声音谜题就会慢慢拥有更多可以比较的线索。"
            ),
            (
                f"如果声音会留下便签，{name}候选者那天写下的就是：{observed}。"
                "便签没有告诉我们发声的原因，只把一个好问题留在了原地。"
                "我们不需要追赶答案，可以让方向、节奏和出现时间在下一次观察中再写一张便签。"
            ),
        ]
        story = stories[variant]
        observation = f"下一次听到相似声音时，在远处记录{name}候选声音的方向和节奏。"
        title = f"{name}留下的声音谜题"
    else:
        stories = [
            (
                f"故事里的{subject}藏在自然的一角，它当时留下了{observed}这几条线索。"
                "我们没有追过去，只在远处把看见和听见的内容记下来。"
                f"这些线索让{name}的身影变得更清楚了一点，却还不足以成为最后答案。"
                "一个好的自然故事，不是急着猜中，而是让每次观察都为它增加新的一页。"
            ),
            (
                f"{name}候选者没有走到故事中央，它只留下了{observed}这几个清楚的词。"
                "它们像放在小路边的路标，指向一个还看不完整的身影。"
                "我们把路标记下来，没有为空白的地方随便添上答案。"
                f"等下一次相遇时，新的线索会继续补上{name}的这段自然故事。"
            ),
            (
                f"如果自然会写便签，{name}候选者那天留下的内容就是：{observed}。"
                "这张便签很短，没有外形、没有答案，却真实记下了那次相遇。"
                "我们把它收好，让未知继续保持未知。"
                f"下一次再听见或看见时，就能为{name}的故事增加一张新便签。"
            ),
        ]
        story = stories[variant]
        observation = f"下一次在远处观察，记下{name}候选声音出现的方向和高度。"
        title = f"{name}留下的自然线索"
    return {"title": title[:28], "story": story, "observation_prompt": observation}


def _observation_fingerprint(observations: list[dict[str, Any]]) -> str:
    stable = [
        {"dimension": item.get("dimension"), "value": item.get("value"), "label": item.get("label")}
        for item in observations
    ]
    return hashlib.sha256(json.dumps(stable, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()[:16]


def _prompt(candidate: dict[str, Any], location: str, story_type: str, observations: list[dict[str, Any]]) -> str:
    angle = "它为什么发声" if story_type == "why_it_calls" else "这个动物怎样度过一天"
    observation_text = "、".join(str(item.get("label")) for item in observations if item.get("value") != "unknown")
    return render_prompt(
        "story.user",
        candidate_name=candidate["name_zh"],
        scientific_name=candidate.get("scientific_name") or "未提供",
        candidate_status=candidate["candidate_status"],
        category=candidate["category"],
        location=location or "杭州",
        angle=angle,
        observation_text=observation_text,
    )


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
        observations: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        if story_type not in STORY_TYPES:
            raise ValueError("暂不支持这种动物故事类型")
        candidate = find_story_candidate(result, candidate_id)
        observations = observations or []
        meaningful = [item for item in observations if item.get("value") != "unknown"]
        if len({str(item.get("dimension")) for item in meaningful}) < 2:
            raise ValueError("请先完成至少两个方面的现场观察，再生成故事")
        fingerprint = _observation_fingerprint(observations)
        started = time.perf_counter()
        warning = ""
        provider = "reviewed-template"
        usage = None
        story = _template_story(candidate, story_type, observations)
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
                                        "content": render_prompt("story.system"),
                                    },
                                    {"role": "user", "content": _prompt(candidate, location, story_type, observations)},
                                ],
                                "temperature": PROMPT_GENERATION["temperature"],
                                "enable_thinking": PROMPT_GENERATION["enable_thinking"],
                                "max_completion_tokens": PROMPT_GENERATION["max_completion_tokens"],
                                "response_format": {"type": PROMPT_GENERATION["response_format"]},
                            },
                        )
                        response.raise_for_status()
                        payload = response.json()
                        raw = _parse_json(payload["choices"][0]["message"]["content"])
                        story = _validate_story(raw, candidate, observations)
                        usage = payload.get("usage")
                        provider = self.model
                except Exception as exc:
                    warning = "模型故事未通过生成或安全校验，已使用安全模板"
                    log_exception(logger, "animal_story_fallback_used", error_type=type(exc).__name__)
        created = {
            "status": "completed",
            "candidate": candidate,
            "story_type": story_type,
            "observations_used": [item.get("label") for item in meaningful],
            "observation_fingerprint": fingerprint,
            **story,
            "candidate_notice": f"这是关于候选动物{candidate['name_zh']}的AI故事，不代表本次录音已经确认物种。",
            "content_label": "AI基于候选信息创作" if provider != "reviewed-template" else "安全模板故事",
            "prompt_version": PROMPT_VERSION,
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
