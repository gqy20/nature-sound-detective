from __future__ import annotations

import json
import math
import os
import shutil
import struct
import subprocess
import time
import wave
from pathlib import Path
from typing import Any, Callable

import httpx
from dotenv import load_dotenv

from app.audio import duration_seconds
from app.config import GENERATED_DIR, ROOT
from app.minimax_service import generate_music as generate_minimax_music
from app.minimax_service import generate_narration


CreationProgress = Callable[[str, str, dict[str, Any] | None], None]


def _api_base() -> str:
    configured = os.getenv("DASHSCOPE_AIGC_BASE_URL", "").rstrip("/")
    if configured:
        return configured
    compatible = os.getenv("DASHSCOPE_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
    return compatible.replace("/compatible-mode/v1", "/api/v1").rstrip("/")


def build_creation_plan(result: dict[str, Any], location: str) -> dict[str, str]:
    card = result.get("card", {})
    title = str(card.get("title") or "自然声音日记")
    primary = str(result.get("primary_sound_type") or "自然环境声")
    explanation = str(card.get("explanation") or "安静倾听自然的声音。")
    question = str(card.get("question") or "你还听到了什么？")
    music_prompt = (
        f"纯音乐，无人声，以{primary}为灵感，自然、轻盈、好奇的儿童探索氛围，"
        "柔和木琴、钢琴、轻打击乐，简单原创旋律，舒缓中速，适合作为亲子自然观察短片背景音乐，"
        "避免宏大、紧张、悲伤和密集鼓点。"
    )
    short_fact = explanation.split("。", 1)[0].strip("。")
    if len(short_fact) > 48:
        short_fact = short_fact[:48].rstrip("，、")
    narration = f"在{location}，我们听见了{primary}。{short_fact}。再安静听一听，它的节奏有什么变化？"
    video_prompt = (
        f"生成一支9:16竖屏、无字幕、无文字、无人物特写的儿童自然科普短片。"
        f"地点氛围：中国杭州城市公园。主题：{title}，主要声音线索：{primary}。"
        f"画面表达：{explanation} 镜头缓慢、真实自然、柔和日光、纪录片质感，"
        "不捕捉、不触摸、不追逐动物；如无法确定具体物种，只表现环境线索，不出现具体动物近景。"
    )
    return {
        "title": title,
        "story": explanation,
        "question": question,
        "music_prompt": music_prompt,
        "narration": narration,
        "video_prompt": video_prompt,
        "location": location,
    }


def _write_tone_bed(path: Path, primary: str, duration: int = 10) -> None:
    sample_rate = 16000
    palettes = {
        "鸟类鸣叫": (523.25, 659.25, 783.99),
        "蛙类鸣叫": (220.00, 293.66, 329.63),
        "昆虫鸣叫": (392.00, 493.88, 587.33),
        "雨水": (261.63, 329.63, 392.00),
        "流水": (293.66, 369.99, 440.00),
        "风和树叶": (246.94, 329.63, 415.30),
    }
    notes = palettes.get(primary, (261.63, 329.63, 392.00))
    frames = bytearray()
    total = sample_rate * duration
    for index in range(total):
        second = index / sample_rate
        note = notes[int(second / 1.25) % len(notes)]
        fade = min(1.0, second / 1.2, (duration - second) / 1.2)
        pulse = 0.58 + 0.42 * math.sin(math.pi * (second % 1.25) / 1.25) ** 2
        value = (
            math.sin(2 * math.pi * note * second)
            + 0.45 * math.sin(2 * math.pi * note * 0.5 * second)
            + 0.22 * math.sin(2 * math.pi * note * 1.5 * second)
        ) / 1.67
        frames.extend(struct.pack("<h", int(32767 * 0.13 * fade * pulse * value)))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(frames)


def create_local_nature_mix(source: Path, destination: Path, primary: str) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法制作自然声混音")
    tone = destination.with_suffix(".tone.wav")
    _write_tone_bed(tone, primary)
    command = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(tone), "-i", str(source),
        "-filter_complex",
        "[0:a]volume=0.72[a0];[1:a]volume=0.55,atrim=duration=10,apad=pad_dur=10[a1];"
        "[a0][a1]amix=inputs=2:duration=first:normalize=0,"
        "afade=t=in:st=0:d=0.8,afade=t=out:st=8.8:d=1.2[out]",
        "-map", "[out]", "-t", "10", "-c:a", "libmp3lame", "-b:a", "160k", str(destination),
    ]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=90)
        if completed.returncode != 0 or not destination.exists():
            raise RuntimeError(completed.stderr.strip()[-500:] or "自然声混音失败")
    finally:
        tone.unlink(missing_ok=True)


def _download(client: httpx.Client, url: str, destination: Path) -> None:
    with client.stream("GET", url) as response:
        response.raise_for_status()
        with destination.open("wb") as handle:
            for chunk in response.iter_bytes():
                handle.write(chunk)


def generate_wan_video(prompt: str, destination: Path, duration: int = 10) -> str:
    if os.getenv("WAN_VIDEO_ENABLED", "true").lower() not in {"1", "true", "yes"}:
        raise RuntimeError("Wan 视频生成未启用")
    api_key = os.environ["DASHSCOPE_API_KEY"]
    base = _api_base()
    model = os.getenv("WAN_VIDEO_MODEL", "wan2.7-t2v")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "X-DashScope-Async": "enable",
    }
    transport = httpx.HTTPTransport(retries=3)
    with httpx.Client(timeout=httpx.Timeout(90, connect=30), transport=transport) as client:
        response = client.post(
            f"{base}/services/aigc/video-generation/video-synthesis",
            headers=headers,
            json={
                "model": model,
                "input": {
                    "prompt": prompt,
                    "negative_prompt": "字幕，文字，水印以外的标识，儿童正脸，捕捉动物，触摸动物，畸形，低清晰度",
                },
                "parameters": {
                    "resolution": "720P", "ratio": "9:16", "duration": duration,
                    "prompt_extend": True, "watermark": True,
                },
            },
        )
        if response.is_error:
            raise RuntimeError(f"Wan2.7 创建失败：{response.text[:800]}")
        payload = response.json()
        task_id = payload.get("output", {}).get("task_id")
        if not task_id:
            raise RuntimeError(f"Wan2.7 没有返回任务ID：{json.dumps(payload, ensure_ascii=False)[:500]}")
        deadline = time.monotonic() + 7 * 60
        while time.monotonic() < deadline:
            time.sleep(10)
            query = client.get(f"{base}/tasks/{task_id}", headers={"Authorization": f"Bearer {api_key}"})
            if query.is_error:
                raise RuntimeError(f"Wan2.7 查询失败：{query.text[:500]}")
            output = query.json().get("output", {})
            status = output.get("task_status")
            if status == "SUCCEEDED":
                url = output.get("video_url")
                if not url:
                    raise RuntimeError("Wan2.7 已完成但没有视频地址")
                _download(client, url, destination)
                return str(task_id)
            if status in {"FAILED", "CANCELED", "UNKNOWN"}:
                raise RuntimeError(f"Wan2.7 任务失败：{output.get('message') or status}")
        raise RuntimeError("Wan2.7 生成超过7分钟")


def mux_story_audio(video: Path, music: Path, narration: Path, nature: Path, destination: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法合成视频")
    completed = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(video), "-stream_loop", "-1", "-i", str(music),
            "-i", str(narration), "-stream_loop", "-1", "-i", str(nature),
            "-filter_complex",
            "[1:a]volume=0.22[bgm];[2:a]volume=1.05,asplit=2[narrsc][narrmix];"
            "[bgm][narrsc]sidechaincompress=threshold=0.035:ratio=8:attack=15:release=350[ducked];"
            "[3:a]volume=0.18[nature];[ducked][nature][narrmix]amix=inputs=3:duration=longest:normalize=0,"
            "alimiter=limit=0.95[aout]",
            "-map", "0:v:0", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac",
            "-b:a", "160k", "-shortest", "-movflags", "+faststart", str(destination),
        ],
        capture_output=True, text=True, timeout=120,
    )
    if completed.returncode != 0 or not destination.exists():
        raise RuntimeError(completed.stderr.strip()[-500:] or "视频与音乐合成失败")


def mux_music(video: Path, music: Path, destination: Path) -> None:
    """Fallback composition used when narration is unavailable."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法合成视频")
    completed = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(video), "-stream_loop", "-1", "-i", str(music),
            "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac",
            "-b:a", "160k", "-shortest", "-movflags", "+faststart", str(destination),
        ],
        capture_output=True, text=True, timeout=120,
    )
    if completed.returncode != 0 or not destination.exists():
        raise RuntimeError(completed.stderr.strip()[-500:] or "视频与音乐合成失败")


class CreationService:
    def __init__(self) -> None:
        load_dotenv(ROOT / ".env")

    def create(
        self,
        job_id: str,
        result: dict[str, Any],
        audio_path: Path,
        location: str,
        progress: CreationProgress,
    ) -> dict[str, Any]:
        GENERATED_DIR.mkdir(parents=True, exist_ok=True)
        plan = build_creation_plan(result, location)
        music_path = GENERATED_DIR / f"{job_id}_minimax_music.mp3"
        narration_path = GENERATED_DIR / f"{job_id}_minimax_narration.mp3"
        raw_video_path = GENERATED_DIR / f"{job_id}_wan.mp4"
        video_path = GENERATED_DIR / f"{job_id}_postcard.mp4"
        music_provider = "minimax-music"
        music_warning = ""
        progress("generating_music", "正在把自然声音变成音乐", {"plan": plan})
        if music_path.exists():
            music_warning = "复用上一次已完成的 MiniMax 音乐"
        else:
            try:
                generate_minimax_music(plan["music_prompt"], music_path)
            except Exception as exc:
                music_provider = "local-nature-remix"
                music_warning = str(exc)
                create_local_nature_mix(audio_path, music_path, result.get("primary_sound_type", ""))

        progress("generating_narration", "正在生成儿童科普旁白", {
            "plan": plan, "music_provider": music_provider, "music_warning": music_warning,
            "music_path": str(music_path), "music_url": f"/api/jobs/{job_id}/creation/music",
        })
        narration_warning = ""
        if not narration_path.exists():
            try:
                generate_narration(plan["narration"], narration_path)
            except Exception as exc:
                narration_warning = str(exc)
        narration_duration = duration_seconds(narration_path) if narration_path.exists() else 0
        video_duration = max(5, min(15, math.ceil(narration_duration + 0.6) if narration_duration else 10))

        creation: dict[str, Any] = {
            "status": "generating_video",
            "stage_message": "正在生成科普短片",
            "plan": plan,
            "music_provider": music_provider,
            "music_warning": music_warning,
            "music_path": str(music_path),
            "music_url": f"/api/jobs/{job_id}/creation/music",
            "narration_provider": "minimax-speech" if narration_path.exists() else "unavailable",
            "narration_warning": narration_warning,
            "narration_text": plan["narration"],
            "narration_path": str(narration_path) if narration_path.exists() else "",
            "narration_url": f"/api/jobs/{job_id}/creation/narration" if narration_path.exists() else "",
            "narration_duration_seconds": narration_duration,
            "video_path": "",
            "video_url": "",
            "video_provider": "wan2.7-t2v",
            "video_error": "",
        }
        progress("generating_video", "正在生成科普短片，通常需要1–5分钟", creation)
        try:
            timed_prompt = f"生成一支{video_duration}秒短片。{plan['video_prompt']}"
            task_id = generate_wan_video(timed_prompt, raw_video_path, video_duration)
            progress("composing_video", "正在合成音乐和画面", {**creation, "wan_task_id": task_id})
            if narration_path.exists():
                mux_story_audio(raw_video_path, music_path, narration_path, audio_path, video_path)
            else:
                mux_music(raw_video_path, music_path, video_path)
            creation.update({
                "status": "completed",
                "stage_message": "自然声音短片制作完成",
                "video_path": str(video_path),
                "video_url": f"/api/jobs/{job_id}/creation/video",
                "wan_task_id": task_id,
            })
        except Exception as exc:
            creation.update({
                "status": "partial",
                "stage_message": "音乐已完成，视频暂时没有生成",
                "video_error": str(exc),
            })
        finally:
            raw_video_path.unlink(missing_ok=True)
        return creation
