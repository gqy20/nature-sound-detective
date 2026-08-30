from __future__ import annotations

import json
import logging
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
from app.dashscope_audio_service import generate_music, generate_narration
from app.generated_prompts import prompt_version, render_prompt
from app.observability import get_logger, log_event, log_exception


logger = get_logger("creation")
PROMPT_VERSION = prompt_version("creation")


CreationProgress = Callable[[str, str, dict[str, Any] | None], None]
TaskCreated = Callable[[str], None]


def _api_base() -> str:
    configured = os.getenv("DASHSCOPE_AIGC_BASE_URL", "").rstrip("/")
    if configured:
        return configured
    compatible = os.getenv("DASHSCOPE_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
    return compatible.replace("/compatible-mode/v1", "/api/v1").rstrip("/")


def build_creation_plan(
    result: dict[str, Any],
    location: str,
    investigation: dict[str, Any] | None = None,
) -> dict[str, str]:
    card = result.get("card", {})
    title = str(card.get("title") or "自然声音日记")
    primary = str(result.get("primary_sound_type") or "自然环境声")
    explanation = str(card.get("explanation") or "安静倾听自然的声音。")
    question = str(card.get("question") or "你还听到了什么？")
    investigation = investigation or {}
    status = str(investigation.get("status") or "not_started")
    observations = investigation.get("observations") or []
    last_choice = str(observations[-1].get("choice") or "") if observations else ""
    observation_summary = {
        "observed": "现场观察也记录到了相同声音线索",
        "not_observed": "现场没有再次观察到相同线索，因此仍保留不确定性",
        "unknown": "现场暂时无法判断，因此保留机器候选",
    }.get(last_choice, "这次作品只依据录音中的机器候选")
    uncertainty = str(result.get("uncertainty") or "具体物种仍待进一步观察")
    music_prompt = render_prompt("creation.server_music", primary=primary)
    short_fact = explanation.split("。", 1)[0].strip("。")
    if len(short_fact) > 48:
        short_fact = short_fact[:48].rstrip("，、")
    narration = render_prompt(
        "creation.server_narration",
        location=location,
        primary=primary,
        short_fact=short_fact,
        observation_summary=observation_summary,
    )
    video_prompt = render_prompt(
        "creation.server_video",
        title=title,
        primary=primary,
        status=status,
        observation_summary=observation_summary,
        uncertainty=uncertainty,
        explanation=explanation,
    )
    return {
        "title": title,
        "story": explanation,
        "question": question,
        "investigation_status": status,
        "observation_summary": observation_summary,
        "uncertainty": uncertainty,
        "music_prompt": music_prompt,
        "narration": narration,
        "video_prompt": video_prompt,
        "prompt_version": PROMPT_VERSION,
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


def trim_audio_excerpt(source: Path, destination: Path, duration: int = 20) -> None:
    """Keep a short, reusable excerpt instead of storing the full generated track."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法裁剪音乐")
    source_duration = duration_seconds(source)
    start = 8 if source_duration > duration + 12 else 0
    target = destination
    temporary = destination.with_suffix(".excerpt.mp3") if source.resolve() == destination.resolve() else destination
    completed = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-ss", str(start),
            "-i", str(source), "-t", str(duration),
            "-af", f"afade=t=in:st=0:d=0.5,afade=t=out:st={max(0, duration - 1)}:d=1",
            "-c:a", "libmp3lame", "-b:a", "192k", str(temporary),
        ],
        capture_output=True, text=True, timeout=120,
    )
    if completed.returncode != 0 or not temporary.exists():
        raise RuntimeError(completed.stderr.strip()[-500:] or "音乐裁剪失败")
    if temporary != target:
        temporary.replace(target)


def create_mock_video(destination: Path, duration: int) -> None:
    """Create a local vertical placeholder so development never spends video credits."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法生成本地占位视频")
    completed = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", f"color=c=#dce8de:s=720x1280:r=24:d={duration}",
            "-vf", "noise=alls=5:allf=t+u,fade=t=in:st=0:d=0.6,fade=t=out:st="
            f"{max(0, duration - 0.8)}:d=0.8",
            "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-an", str(destination),
        ],
        capture_output=True, text=True, timeout=120,
    )
    if completed.returncode != 0 or not destination.exists():
        raise RuntimeError(completed.stderr.strip()[-500:] or "本地占位视频生成失败")


def reuse_video(source: Path, destination: Path, duration: int) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("服务器没有安装 ffmpeg，无法复用演示视频")
    completed = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-stream_loop", "-1",
            "-i", str(source), "-t", str(duration), "-map", "0:v:0", "-an",
            "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", str(destination),
        ],
        capture_output=True, text=True, timeout=180,
    )
    if completed.returncode != 0 or not destination.exists():
        raise RuntimeError(completed.stderr.strip()[-500:] or "演示视频复用失败")


def _download(client: httpx.Client, url: str, destination: Path) -> None:
    with client.stream("GET", url) as response:
        response.raise_for_status()
        with destination.open("wb") as handle:
            for chunk in response.iter_bytes():
                handle.write(chunk)


def generate_wan_video(
    prompt: str,
    destination: Path,
    duration: int = 5,
    existing_task_id: str = "",
    on_task_created: TaskCreated | None = None,
) -> str:
    if os.getenv("WAN_VIDEO_ENABLED", "true").lower() not in {"1", "true", "yes"}:
        raise RuntimeError("Wan 视频生成未启用")
    api_key = os.environ["DASHSCOPE_API_KEY"]
    base = _api_base()
    model = os.getenv("WAN_VIDEO_MODEL", "wan3.0-video")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "X-DashScope-Async": "enable",
    }
    transport = httpx.HTTPTransport(retries=3)
    with httpx.Client(timeout=httpx.Timeout(90, connect=30), transport=transport) as client:
        task_id = existing_task_id
        if not task_id:
            response = client.post(
                f"{base}/services/aigc/video-generation/video-synthesis",
                headers=headers,
                json={
                    "model": model,
                    "input": {
                        "prompt": prompt,
                        "negative_prompt": render_prompt(
                            "creation.server_video_negative"
                        ),
                    },
                    "parameters": {
                        "resolution": "480P", "ratio": "9:16", "duration": duration,
                        "audio": False, "prompt_extend": True, "watermark": True,
                    },
                },
            )
            if response.is_error:
                raise RuntimeError(f"Wan 视频创建失败：{response.text[:800]}")
            payload = response.json()
            task_id = str(payload.get("output", {}).get("task_id") or "")
            if not task_id:
                raise RuntimeError(f"Wan 视频没有返回任务ID：{json.dumps(payload, ensure_ascii=False)[:500]}")
            if on_task_created:
                on_task_created(task_id)
        deadline = time.monotonic() + 7 * 60
        while time.monotonic() < deadline:
            time.sleep(10)
            query = client.get(f"{base}/tasks/{task_id}", headers={"Authorization": f"Bearer {api_key}"})
            if query.is_error:
                raise RuntimeError(f"Wan 视频查询失败：{query.text[:500]}")
            output = query.json().get("output", {})
            status = output.get("task_status")
            if status == "SUCCEEDED":
                url = output.get("video_url")
                if not url:
                    raise RuntimeError("Wan 视频已完成但没有视频地址")
                _download(client, url, destination)
                return str(task_id)
            if status in {"FAILED", "CANCELED", "UNKNOWN"}:
                raise RuntimeError(f"Wan 视频任务失败：{output.get('message') or status}")
        raise RuntimeError("Wan 视频生成超过7分钟")


def prepare_video(
    prompt: str,
    destination: Path,
    duration: int,
    existing_task_id: str = "",
    on_task_created: TaskCreated | None = None,
) -> tuple[str, str]:
    """Select an explicit-cost video backend. Live calls require WAN_VIDEO_MODE=live."""
    mode = os.getenv("WAN_VIDEO_MODE", "mock").strip().lower()
    if mode == "live":
        task_id = generate_wan_video(
            prompt, destination, duration, existing_task_id=existing_task_id,
            on_task_created=on_task_created,
        )
        return os.getenv("WAN_VIDEO_MODEL", "wan3.0-video"), task_id
    if mode == "reuse":
        configured = os.getenv("WAN_VIDEO_REUSE_PATH", "").strip()
        candidates = [Path(configured)] if configured else sorted(
            GENERATED_DIR.glob("*_postcard.mp4"), key=lambda path: path.stat().st_mtime, reverse=True
        )
        source = next((path for path in candidates if path.exists()), None)
        if source:
            reuse_video(source, destination, duration)
            return "reused-demo-video", ""
    create_mock_video(destination, duration)
    return "local-mock-video", ""


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
        previous_creation: dict[str, Any] | None = None,
        investigation: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        GENERATED_DIR.mkdir(parents=True, exist_ok=True)
        plan = build_creation_plan(result, location, investigation)
        music_path = GENERATED_DIR / f"{job_id}_dashscope_music.mp3"
        narration_path = GENERATED_DIR / f"{job_id}_dashscope_narration.mp3"
        raw_video_path = GENERATED_DIR / f"{job_id}_wan.mp4"
        video_path = GENERATED_DIR / f"{job_id}_postcard.mp4"
        music_provider = "dashscope-fun-music"
        music_warning = ""
        progress("generating_music", "正在把自然声音变成音乐", {"plan": plan})
        if music_path.exists():
            music_warning = "复用上一次已完成的百炼音乐"
            excerpt_seconds = int(os.getenv("DASHSCOPE_MUSIC_EXCERPT_SECONDS", "20"))
            if duration_seconds(music_path) > excerpt_seconds + 1:
                trim_audio_excerpt(music_path, music_path, excerpt_seconds)
                music_warning += "，并裁剪为短片片段"
        else:
            full_music_path = music_path.with_suffix(".full.mp3")
            try:
                generate_music(plan["music_prompt"], full_music_path)
                trim_audio_excerpt(
                    full_music_path, music_path,
                    int(os.getenv("DASHSCOPE_MUSIC_EXCERPT_SECONDS", "20")),
                )
            except Exception as exc:
                log_exception(logger, "music_provider_fallback", job_id=job_id)
                music_provider = "local-nature-remix"
                music_warning = str(exc)
                create_local_nature_mix(audio_path, music_path, result.get("primary_sound_type", ""))
            finally:
                full_music_path.unlink(missing_ok=True)

        progress("generating_narration", "正在生成儿童科普旁白", {
            "plan": plan, "music_provider": music_provider, "music_warning": music_warning,
            "music_path": str(music_path), "music_url": f"/api/jobs/{job_id}/creation/music",
        })
        narration_warning = ""
        if not narration_path.exists():
            try:
                generate_narration(plan["narration"], narration_path)
            except Exception as exc:
                log_exception(logger, "narration_generation_skipped", job_id=job_id)
                narration_warning = str(exc)
        narration_duration = duration_seconds(narration_path) if narration_path.exists() else 0
        video_duration = 5
        prior = previous_creation or {}

        creation: dict[str, Any] = {
            "status": "generating_video",
            "stage_message": "正在生成科普短片",
            "plan": plan,
            "music_provider": music_provider,
            "music_warning": music_warning,
            "music_path": str(music_path),
            "music_url": f"/api/jobs/{job_id}/creation/music",
            "narration_provider": "dashscope-qwen-audio-tts" if narration_path.exists() else "unavailable",
            "narration_warning": narration_warning,
            "narration_text": plan["narration"],
            "narration_path": str(narration_path) if narration_path.exists() else "",
            "narration_url": f"/api/jobs/{job_id}/creation/narration" if narration_path.exists() else "",
            "narration_duration_seconds": narration_duration,
            "video_path": "",
            "video_url": "",
            "video_provider": str(prior.get("video_provider") or "pending"),
            "video_error": "",
            "wan_task_id": str(prior.get("wan_task_id") or ""),
        }
        video_mode = os.getenv("WAN_VIDEO_MODE", "mock").strip().lower()
        stage_message = (
            "正在生成科普短片，通常需要1–5分钟" if video_mode == "live"
            else "正在准备本地演示画面"
        )
        progress("generating_video", stage_message, creation)
        try:
            timed_prompt = render_prompt(
                "creation.server_video_timed",
                duration_seconds=video_duration,
                video_prompt=plan["video_prompt"],
            )
            def persist_task(task_id: str) -> None:
                creation.update({
                    "wan_task_id": task_id,
                    "video_provider": os.getenv("WAN_VIDEO_MODEL", "wan3.0-video"),
                })
                progress("generating_video", "视频任务已提交，正在等待结果", creation)

            provider, task_id = prepare_video(
                timed_prompt, raw_video_path, video_duration,
                existing_task_id=str(prior.get("wan_task_id") or ""),
                on_task_created=persist_task,
            )
            creation.update({"video_provider": provider, "wan_task_id": task_id})
            progress("composing_video", "正在合成音乐、旁白和自然原声", creation)
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
            log_exception(logger, "video_generation_partial", job_id=job_id, video_mode=video_mode)
            creation.update({
                "status": "partial",
                "stage_message": "音乐已完成，视频暂时没有生成",
                "video_error": str(exc),
            })
        finally:
            raw_video_path.unlink(missing_ok=True)
        return creation
