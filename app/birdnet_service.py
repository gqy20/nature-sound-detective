from __future__ import annotations

import logging
import threading
import time
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

from app.config import ROOT
from app.observability import get_logger, log_event, log_exception
from app.species_catalog import load_hangzhou_birdnet_catalog


logger = get_logger("birdnet")
MODEL_PATH = ROOT / "mobile" / "assets" / "models" / "birdnet.tflite"
SAMPLE_RATE = 48_000
WINDOW_SAMPLES = 144_000


@dataclass(frozen=True)
class BirdNetWindows:
    scores: np.ndarray
    embeddings: np.ndarray
    starts: np.ndarray
    ends: np.ndarray

    @property
    def count(self) -> int:
        return int(self.scores.shape[0])


def _read_waveform(audio_path: Path) -> np.ndarray:
    with wave.open(str(audio_path), "rb") as source:
        channels = source.getnchannels()
        sample_width = source.getsampwidth()
        sample_rate = source.getframerate()
        frames = source.readframes(source.getnframes())
    if sample_width != 2 or sample_rate != SAMPLE_RATE:
        raise ValueError("BirdNET 输入必须是 48 kHz、16-bit PCM WAV")
    samples = np.frombuffer(frames, dtype="<i2").astype(np.float32)
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return np.ascontiguousarray(samples / 32768.0, dtype=np.float32)


def _window_waveform(waveform: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if not waveform.size:
        return (
            np.empty((0, WINDOW_SAMPLES), dtype=np.float32),
            np.empty(0, dtype=np.float32),
            np.empty(0, dtype=np.float32),
        )
    count = (len(waveform) + WINDOW_SAMPLES - 1) // WINDOW_SAMPLES
    windows = np.zeros((count, WINDOW_SAMPLES), dtype=np.float32)
    starts = np.arange(count, dtype=np.float32) * (WINDOW_SAMPLES / SAMPLE_RATE)
    ends = np.empty(count, dtype=np.float32)
    for index in range(count):
        offset = index * WINDOW_SAMPLES
        available = min(WINDOW_SAMPLES, len(waveform) - offset)
        windows[index, :available] = waveform[offset : offset + available]
        ends[index] = (offset + available) / SAMPLE_RATE
    return windows, starts, ends


class BirdNetAnalyzer:
    """One TFLite forward pass produces bird scores and non-bird embeddings."""

    def __init__(self, model_path: Path = MODEL_PATH, *, num_threads: int = 2) -> None:
        self.model_path = model_path
        self.num_threads = num_threads
        self._interpreter: tf.lite.Interpreter | None = None
        self._lock = threading.Lock()

    def _load(self) -> tf.lite.Interpreter:
        if self._interpreter is None:
            started = time.perf_counter()
            log_event(logger, logging.INFO, "birdnet_model_load_started", model_version="2.4-fp16")
            try:
                interpreter = tf.lite.Interpreter(
                    model_path=str(self.model_path), num_threads=self.num_threads
                )
                interpreter.allocate_tensors()
                self._interpreter = interpreter
            except Exception:
                log_exception(logger, "birdnet_model_load_failed", model_version="2.4-fp16")
                raise
            log_event(
                logger,
                logging.INFO,
                "birdnet_model_load_completed",
                model_version="2.4-fp16",
                duration_ms=round((time.perf_counter() - started) * 1000),
            )
        return self._interpreter

    @property
    def loaded(self) -> bool:
        return self._interpreter is not None

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        with self._lock:
            self._load()
        return {
            "status": "ready",
            "duration_ms": round((time.perf_counter() - started) * 1000),
        }

    def infer_windows(self, audio_path: Path) -> BirdNetWindows:
        started = time.perf_counter()
        waveform = _read_waveform(audio_path)
        windows, starts, ends = _window_waveform(waveform)
        if not len(windows):
            return BirdNetWindows(
                scores=np.empty((0, 6522), dtype=np.float32),
                embeddings=np.empty((0, 1024), dtype=np.float32),
                starts=starts,
                ends=ends,
            )
        with self._lock:
            interpreter = self._load()
            input_detail = interpreter.get_input_details()[0]
            expected_shape = [len(windows), WINDOW_SAMPLES]
            if input_detail["shape"].tolist() != expected_shape:
                interpreter.resize_tensor_input(input_detail["index"], expected_shape)
                interpreter.allocate_tensors()
                input_detail = interpreter.get_input_details()[0]
            interpreter.set_tensor(input_detail["index"], windows)
            interpreter.invoke()
            outputs = interpreter.get_output_details()
            logits = np.asarray(interpreter.get_tensor(outputs[0]["index"]), dtype=np.float32)
            scores = (1.0 / (1.0 + np.exp(-logits))).astype(np.float32, copy=False)
            embeddings = np.asarray(
                interpreter.get_tensor(outputs[1]["index"]), dtype=np.float32
            )
        if scores.shape != (len(windows), 6522) or embeddings.shape != (
            len(windows),
            1024,
        ):
            raise RuntimeError(
                f"BirdNET 输出形状异常: scores={scores.shape}, embeddings={embeddings.shape}"
            )
        log_event(
            logger,
            logging.INFO,
            "birdnet_shared_inference_completed",
            duration_ms=round((time.perf_counter() - started) * 1000),
            window_count=len(windows),
        )
        return BirdNetWindows(scores, embeddings, starts, ends)

    def summarize(self, windows: BirdNetWindows) -> dict[str, Any]:
        species = load_hangzhou_birdnet_catalog()
        detections: list[dict[str, Any]] = []
        for item in species:
            if not windows.count:
                continue
            column = windows.scores[:, item.output_index]
            best_index = int(np.argmax(column))
            confidence = float(column[best_index])
            if confidence < 0.05:
                continue
            detections.append(
                {
                    "name_zh": item.name_zh,
                    "label": item.birdnet_label,
                    "confidence": round(confidence, 4),
                    "start_seconds": round(float(windows.starts[best_index]), 3),
                    "end_seconds": round(float(windows.ends[best_index]), 3),
                    "status": "likely" if confidence >= 0.5 else "candidate",
                }
            )
        detections.sort(key=lambda item: item["confidence"], reverse=True)
        return {
            "model": "BirdNET acoustic 2.4 FP16",
            "scope": f"杭州全年地理先验候选鸟类（{len(species)}种）",
            "detections": detections[:3],
        }

    def analyze(self, audio_path: Path) -> dict[str, Any]:
        started = time.perf_counter()
        windows = self.infer_windows(audio_path)
        result = self.summarize(windows)
        log_event(
            logger,
            logging.INFO,
            "birdnet_inference_completed",
            duration_ms=round((time.perf_counter() - started) * 1000),
            window_count=windows.count,
            detection_count=len(result["detections"]),
        )
        return result
