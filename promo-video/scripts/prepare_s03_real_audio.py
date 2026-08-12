"""Prepare S03's category audio bed and sample-derived waveform data.

The waveform JSON is computed from the exact PCM clips written to the nature
bed.  It is therefore an auditable representation of the audio heard in each
category interval, rather than decorative motion.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import wave
from pathlib import Path

import numpy as np


RATE = 48_000
CATEGORIES = (
    ("鸟鸣", 1.30),
    ("蛙声", 1.10),
    ("虫鸣", 1.10),
    ("流水", 1.20),
    ("风雨", 2.30),
)


def decode(path: Path, start: float | None = None, duration: float | None = None) -> np.ndarray:
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error"]
    if start is not None:
        cmd += ["-ss", f"{start:.3f}"]
    cmd += ["-i", str(path)]
    if duration is not None:
        cmd += ["-t", f"{duration:.3f}"]
    cmd += ["-vn", "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.check_output(cmd), dtype="<f4").copy()


def strongest_window(audio: np.ndarray, seconds: float) -> tuple[np.ndarray, float]:
    wanted = round(seconds * RATE)
    if len(audio) <= wanted:
        return np.pad(audio, (0, max(0, wanted - len(audio))))[:wanted], 0.0
    block = max(1, round(0.025 * RATE))
    usable = audio[: len(audio) // block * block]
    energy = np.mean(usable.reshape(-1, block) ** 2, axis=1)
    blocks = max(1, round(seconds * RATE / block))
    rolling = np.convolve(energy, np.ones(blocks), mode="valid")
    # Avoid a single isolated handling transient by choosing the first window
    # at or above the 98th percentile of sustained energy.
    threshold = float(np.percentile(rolling, 98))
    candidates = np.flatnonzero(rolling >= threshold)
    start_block = int(candidates[0] if len(candidates) else np.argmax(rolling))
    start = start_block * block
    return audio[start : start + wanted].copy(), start / RATE


def finish_clip(audio: np.ndarray, seconds: float, target_rms: float = 0.115) -> np.ndarray:
    wanted = round(seconds * RATE)
    audio = np.pad(audio, (0, max(0, wanted - len(audio))))[:wanted]
    audio -= float(np.mean(audio))
    rms = float(np.sqrt(np.mean(audio**2)) + 1e-9)
    gain = min(target_rms / rms, 12.0)
    audio *= gain
    peak = float(np.max(np.abs(audio)) + 1e-9)
    if peak > 0.86:
        audio *= 0.86 / peak
    fade = min(round(0.045 * RATE), len(audio) // 3)
    if fade:
        ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)
        audio[:fade] *= ramp
        audio[-fade:] *= ramp[::-1]
    return audio.astype(np.float32)


def display_waveform(audio: np.ndarray, count: int = 180) -> list[float]:
    chunks = np.array_split(np.abs(audio), count)
    values = np.array([np.sqrt(np.mean(chunk**2)) if len(chunk) else 0 for chunk in chunks])
    ceiling = float(np.percentile(values, 98) + 1e-9)
    values = np.clip(values / ceiling, 0.0, 1.0)
    # Preserve quiet gaps while ensuring the trace remains legible on video.
    return [round(float(0.06 + 0.94 * value), 5) for value in values]


def write_wav(path: Path, audio: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bird", type=Path, required=True)
    parser.add_argument("--frog", type=Path, required=True)
    parser.add_argument("--insect", type=Path, required=True)
    parser.add_argument("--water", type=Path, required=True)
    parser.add_argument("--wind", type=Path, required=True)
    parser.add_argument("--rain", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for path in (args.bird, args.frog, args.insect, args.water, args.wind, args.rain):
        if not path.exists():
            raise SystemExit(f"Missing source audio: {path}")

    records: list[dict] = []
    clips: list[np.ndarray] = []

    # Use the user's own field recording for the generic 鸟鸣 interval.
    bird = finish_clip(decode(args.bird, start=11.5, duration=1.30), 1.30)
    clips.append(bird)
    records.append({"label": "鸟鸣", "source": str(args.bird.resolve()), "start_seconds": 11.5})

    for label, path, seconds in (
        ("蛙声", args.frog, 1.10),
        ("虫鸣", args.insect, 1.10),
        ("流水", args.water, 1.20),
    ):
        selected, start = strongest_window(decode(path), seconds)
        clips.append(finish_clip(selected, seconds))
        records.append({"label": label, "source": str(path.resolve()), "start_seconds": round(start, 3)})

    wind_raw, wind_start = strongest_window(decode(args.wind), 2.30)
    rain_raw, rain_start = strongest_window(decode(args.rain), 2.30)
    wind = finish_clip(wind_raw, 2.30, target_rms=0.075)
    rain = finish_clip(rain_raw, 2.30, target_rms=0.090)
    weather = finish_clip(wind * 0.58 + rain * 0.72, 2.30, target_rms=0.115)
    clips.append(weather)
    records.append({
        "label": "风雨",
        "sources": [str(args.wind.resolve()), str(args.rain.resolve())],
        "start_seconds": [round(wind_start, 3), round(rain_start, 3)],
    })

    bed_path = args.output_dir / "s03-category-nature-bed-v016.wav"
    write_wav(bed_path, np.concatenate(clips))

    cursor = 0.0
    for index, (record, (label, seconds), clip) in enumerate(zip(records, CATEGORIES, clips), start=1):
        clip_path = args.output_dir / f"{index:02d}-{label}-v016.wav"
        write_wav(clip_path, clip)
        record.update({
            "duration_seconds": seconds,
            "timeline_start_seconds": round(cursor, 2),
            "timeline_end_seconds": round(cursor + seconds, 2),
            "clip": str(clip_path.resolve()),
            "clip_sha256": sha256(clip_path),
            "waveform": display_waveform(clip),
        })
        cursor += seconds

    payload = {
        "description": "Waveforms sampled from the exact mono nature-audio clips used in S03 v016.",
        "sample_rate": RATE,
        "duration_seconds": round(cursor, 2),
        "nature_bed": str(bed_path.resolve()),
        "nature_bed_sha256": sha256(bed_path),
        "categories": records,
    }
    (args.output_dir / "s03-waveforms-v016.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
