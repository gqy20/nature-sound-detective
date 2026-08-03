from __future__ import annotations

import math
from pathlib import Path
import wave

import numpy as np


def read_pcm16_mono(path: Path, *, sample_rate: int = 48000) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        if (
            handle.getnchannels() != 1
            or handle.getsampwidth() != 2
            or handle.getframerate() != sample_rate
        ):
            raise ValueError(f"音频必须是 {sample_rate} Hz、16-bit 单声道 PCM WAV: {path}")
        values = np.frombuffer(handle.readframes(handle.getnframes()), dtype="<i2")
    return values.astype(np.float32) / 32768.0


def write_pcm16_mono(path: Path, samples: np.ndarray, *, sample_rate: int = 48000) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm.tobytes())


def signal_rms(samples: np.ndarray) -> float:
    if not samples.size:
        return 0.0
    return float(np.sqrt(np.mean(np.square(samples.astype(np.float64)))))


def fit_noise(noise: np.ndarray, length: int, rng: np.random.Generator) -> np.ndarray:
    if not noise.size:
        raise ValueError("背景音频不能为空")
    if noise.size >= length:
        start = int(rng.integers(0, noise.size - length + 1))
        return noise[start : start + length].copy()
    repeats = math.ceil(length / noise.size)
    tiled = np.tile(noise, repeats)
    offset = int(rng.integers(0, noise.size)) if noise.size > 1 else 0
    return np.roll(tiled, -offset)[:length].copy()


def mix_at_snr(
    target: np.ndarray,
    noise: np.ndarray,
    snr_db: float,
    *,
    rng: np.random.Generator,
) -> np.ndarray:
    fitted_noise = fit_noise(noise, len(target), rng)
    target_level = max(signal_rms(target), 1e-5)
    noise_level = max(signal_rms(fitted_noise), 1e-5)
    desired_noise_level = target_level / (10.0 ** (snr_db / 20.0))
    mixed = target + fitted_noise * (desired_noise_level / noise_level)
    peak = float(np.max(np.abs(mixed))) if mixed.size else 0.0
    if peak > 0.98:
        mixed = mixed * (0.98 / peak)
    return mixed.astype(np.float32)


def apply_stress_condition(
    target: np.ndarray,
    noise: np.ndarray,
    condition: str,
    *,
    rng: np.random.Generator,
    sample_rate: int = 48000,
) -> np.ndarray:
    if condition.startswith("snr_"):
        return mix_at_snr(target, noise, float(condition.removeprefix("snr_")), rng=rng)
    if condition == "quiet":
        return (target * 0.15).astype(np.float32)
    if condition == "reverb":
        delayed = max(1, int(sample_rate * 0.12))
        result = target.copy()
        if result.size > delayed:
            result[delayed:] += target[:-delayed] * 0.35
        if result.size > delayed * 2:
            result[delayed * 2 :] += target[: -delayed * 2] * 0.15
        peak = float(np.max(np.abs(result))) if result.size else 0.0
        return (result * min(1.0, 0.98 / max(peak, 1e-6))).astype(np.float32)
    if condition == "phone_band":
        # A small moving average suppresses high frequencies; down/up sampling suppresses
        # additional detail and approximates a constrained phone microphone path.
        kernel = np.ones(5, dtype=np.float32) / 5.0
        filtered = np.convolve(target, kernel, mode="same")
        reduced = filtered[::3]
        restored = np.interp(
            np.arange(target.size),
            np.arange(reduced.size) * 3,
            reduced,
        )
        return (restored * 0.7).astype(np.float32)
    raise ValueError(f"未知压力条件: {condition}")
