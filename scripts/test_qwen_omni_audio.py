"""Run a constrained Qwen3.5-Omni nature-sound analysis.

The API key and endpoint are loaded from the project-level .env file.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path

import numpy as np
import soundfile as sf
from dotenv import load_dotenv
from openai import OpenAI


ROOT = Path(__file__).resolve().parents[1]

PROMPT = """你是一名谨慎的自然声音分析助手。请只根据录音本身分析，不要根据文件名猜测。
判断录音是否包含以下声音，可多选：鸟类鸣叫、蛙类鸣叫、昆虫鸣叫、雨水、风和树叶、流水、
人声、脚步、交通或机械噪声、其他、无法判断。

请严格返回一个 JSON 对象，不要使用 Markdown，字段如下：
{
  "sound_types": ["声音大类"],
  "dominant_sound": "主要声音或无法判断",
  "possible_species": ["只有证据充分时填写候选物种，否则为空"],
  "confidence_level": "high|medium|low",
  "evidence": ["从节奏、音高、重复方式、背景声等方面给出简短依据"],
  "uncertainty": "说明不能确定的地方"
}
具体物种证据不足时必须返回空数组，不得编造。"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_source", help="Local path or public HTTP(S) URL")
    parser.add_argument("--model", default="qwen3.5-omni-plus")
    parser.add_argument("--voice-output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_dotenv(ROOT / ".env")
    is_url = args.audio_source.startswith(("http://", "https://"))
    if is_url:
        audio_data = args.audio_source
        audio_format = Path(args.audio_source.split("?", 1)[0]).suffix.lower().lstrip(".")
    else:
        audio_path = Path(args.audio_source).resolve()
        if not audio_path.is_file():
            raise FileNotFoundError(audio_path)
        encoded = base64.b64encode(audio_path.read_bytes()).decode("ascii")
        if len(encoded.encode("ascii")) >= 10 * 1024 * 1024:
            raise ValueError("Base64 audio input must be smaller than 10 MB")
        audio_data = f"data:;base64,{encoded}"
        audio_format = audio_path.suffix.lower().lstrip(".")
    if audio_format not in {"wav", "mp3", "aac", "amr", "3gp", "3gpp"}:
        raise ValueError(f"Unsupported audio format: {audio_format}")

    client = OpenAI(
        api_key=os.environ["DASHSCOPE_API_KEY"],
        base_url=os.environ.get(
            "DASHSCOPE_BASE_URL",
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
        ),
    )
    wants_voice = args.voice_output is not None
    request = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_audio",
                        "input_audio": {
                            "data": audio_data,
                            "format": audio_format,
                        },
                    },
                    {"type": "text", "text": PROMPT},
                ],
            }
        ],
        "modalities": ["text", "audio"] if wants_voice else ["text"],
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if wants_voice:
        request["audio"] = {"voice": "Tina", "format": "wav"}

    text_parts: list[str] = []
    audio_parts: list[str] = []
    usage = None
    for chunk in client.chat.completions.create(**request):
        if chunk.choices:
            delta = chunk.choices[0].delta
            if delta.content:
                text_parts.append(delta.content)
            if getattr(delta, "audio", None):
                audio_parts.append(delta.audio.get("data", ""))
        elif chunk.usage:
            usage = chunk.usage

    raw_text = "".join(text_parts).strip()
    try:
        parsed = json.loads(raw_text)
        print(json.dumps(parsed, ensure_ascii=False, indent=2))
    except json.JSONDecodeError:
        print(raw_text)

    if usage:
        print(f"\nusage={usage.model_dump_json()}")

    if wants_voice and audio_parts:
        pcm = np.frombuffer(base64.b64decode("".join(audio_parts)), dtype=np.int16)
        args.voice_output.parent.mkdir(parents=True, exist_ok=True)
        sf.write(args.voice_output, pcm, samplerate=24_000)
        print(f"voice_output={args.voice_output.resolve()}")


if __name__ == "__main__":
    main()
