from __future__ import annotations

import base64
import json
import os
import re
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from openai import OpenAI

from app.config import ROOT


SYSTEM_PROMPT = """你是面向儿童亲子自然观察的声音分析助手。你必须谨慎，不得根据文件名猜测，不得把不确定的声音说成确定物种。"""


def build_prompt(location: str) -> str:
    return f"""录音地点信息：{location or '杭州，具体地点未知'}。
请分析随附的户外录音，判断是否含有以下声音，可多选：鸟类鸣叫、蛙类鸣叫、昆虫鸣叫、雨水、流水、风和树叶、人声、脚步、交通或机械噪声、其他、无法判断。

严格返回一个JSON对象，不要使用Markdown：
{{
  "sound_types": ["声音大类"],
  "primary_sound_type": "最确定、最主要的一类声音；无法确定时填无法判断",
  "possible_sound_types": ["证据不足但可能存在的声音，只放次要猜测"],
  "dominant_sound": "主要声音或无法判断",
  "possible_species": ["只有证据充分时才填写候选物种"],
  "confidence_level": "high|medium|low",
  "evidence": ["最多三条简短听觉依据"],
  "uncertainty": "不能确认的内容",
  "child_title": "不超过14字的儿童声音卡片标题",
  "child_explanation": "60至100字、只围绕primary_sound_type解释，不得写入possible_sound_types，不编造物种事实，不用一定等绝对表述",
  "observation_question": "一个非侵入式观察问题，只允许安静倾听、远距离观看和记录，不建议拨动草叶、追逐、抓取或触摸生物",
  "safety_note": "一句与采集行为相关的通用户外安全提示；除非声音和地点证据都明确，否则不得推断附近存在水域、道路或动物"
}}
如果不能确认具体物种，possible_species必须为空数组。一个声音只是疑似存在时，必须放入possible_sound_types，不能放入sound_types。confidence_level是整段录音的谨慎判断，多种声音混合时不得返回high。"""


def _parse_json(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s*```$", "", cleaned)
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
        if not match:
            raise ValueError("模型没有返回可解析的JSON")
        value = json.loads(match.group(0))
    if not isinstance(value, dict):
        raise ValueError("模型结果不是JSON对象")
    return value


class QwenNatureAnalyzer:
    def __init__(self, model: str = "qwen3.5-omni-plus") -> None:
        load_dotenv(ROOT / ".env")
        api_key = os.getenv("DASHSCOPE_API_KEY")
        if not api_key:
            raise RuntimeError("缺少DASHSCOPE_API_KEY，请先配置.env")
        self.model = model
        self.client = OpenAI(
            api_key=api_key,
            base_url=os.getenv(
                "DASHSCOPE_BASE_URL",
                "https://dashscope.aliyuncs.com/compatible-mode/v1",
            ),
            timeout=120,
            max_retries=1,
        )

    def analyze(self, audio_path: Path, location: str) -> dict[str, Any]:
        encoded = base64.b64encode(audio_path.read_bytes()).decode("ascii")
        stream = self.client.chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_audio",
                            "input_audio": {
                                "data": f"data:;base64,{encoded}",
                                "format": "wav",
                            },
                        },
                        {"type": "text", "text": build_prompt(location)},
                    ],
                },
            ],
            modalities=["text"],
            stream=True,
            stream_options={"include_usage": True},
        )
        text_parts: list[str] = []
        usage: dict[str, Any] | None = None
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                text_parts.append(chunk.choices[0].delta.content)
            elif chunk.usage:
                usage = chunk.usage.model_dump()
        result = _parse_json("".join(text_parts))
        result["model"] = self.model
        result["usage"] = usage
        return result
