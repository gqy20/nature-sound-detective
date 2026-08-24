from __future__ import annotations

import csv
import logging
import threading
import time
import wave
from pathlib import Path
from typing import Any

import numpy as np

from app.config import ROOT
from app.observability import get_logger, log_event


logger = get_logger("yamnet")

MODEL_PATH = ROOT / "mobile" / "assets" / "models" / "yamnet.tflite"
LABEL_PATH = ROOT / "mobile" / "assets" / "labels" / "yamnet.csv"
WINDOW_SAMPLES = 15_600
HOP_SAMPLES = 7_800
SAMPLE_RATE = 16_000

CATEGORIES = {
    "bird": {
        "name_zh": "鸟类鸣叫",
        "threshold": 0.20,
        "labels": {
            "Bird", "Bird vocalization, bird call, bird song", "Chirp, tweet",
            "Squawk", "Pigeon, dove", "Crow", "Owl", "Gull, seagull",
        },
    },
    "frog": {"name_zh": "蛙类鸣叫", "threshold": 0.15, "labels": {"Frog"}},
    "insect": {
        "name_zh": "昆虫鸣叫",
        "threshold": 0.18,
        "labels": {"Insect", "Cricket", "Mosquito", "Fly, housefly", "Bee, wasp, etc."},
    },
    "rain": {
        "name_zh": "雨水", "threshold": 0.18,
        "labels": {"Rain", "Raindrop", "Rain on surface"},
    },
    "running_water": {
        "name_zh": "流水", "threshold": 0.18,
        "labels": {"Water", "Stream", "Waterfall", "Gurgling"},
    },
    "wind": {
        "name_zh": "风和树叶", "threshold": 0.18,
        "labels": {"Wind", "Rustling leaves", "Wind noise (microphone)", "Rustle"},
    },
    "speech": {
        "name_zh": "人声", "threshold": 0.25,
        "labels": {
            "Speech", "Child speech, kid speaking", "Conversation", "Narration, monologue",
            "Hubbub, speech noise, speech babble",
        },
    },
    "footsteps": {
        "name_zh": "脚步", "threshold": 0.20,
        "labels": {"Walk, footsteps", "Run"},
    },
    "traffic_machine": {
        "name_zh": "交通或机械噪声", "threshold": 0.22,
        "labels": {
            "Vehicle", "Motor vehicle (road)", "Car", "Bus", "Truck", "Motorcycle",
            "Traffic noise, roadway noise", "Train", "Aircraft", "Engine", "Tools", "Power tool",
        },
    },
}


def _interpreter_class():
    try:
        from tflite_runtime.interpreter import Interpreter

        return Interpreter
    except ImportError:
        import tensorflow as tf

        return tf.lite.Interpreter


def _read_pcm16_mono(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2 or handle.getframerate() != SAMPLE_RATE:
            raise ValueError("YAMNet输入必须是16 kHz、单声道、16-bit PCM WAV")
        frames = handle.readframes(handle.getnframes())
    if not frames:
        raise ValueError("YAMNet没有读取到有效音频")
    return np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0


class YamNetAnalyzer:
    def __init__(self, model_path: Path = MODEL_PATH, label_path: Path = LABEL_PATH) -> None:
        self.model_path = model_path
        self.label_path = label_path
        self._lock = threading.Lock()
        self._inference_lock = threading.Lock()
        self._interpreter = None
        self._indices: dict[str, list[int]] = {}

    def preload(self) -> dict[str, Any]:
        started = time.perf_counter()
        self._load()
        return {
            "status": "ready",
            "model": "YAMNet tflite-1",
            "duration_ms": round((time.perf_counter() - started) * 1000),
        }

    def _load(self) -> None:
        if self._interpreter is not None:
            return
        with self._lock:
            if self._interpreter is not None:
                return
            if not self.model_path.is_file() or not self.label_path.is_file():
                raise FileNotFoundError("缺少YAMNet模型或标签文件")
            Interpreter = _interpreter_class()
            interpreter = Interpreter(model_path=str(self.model_path), num_threads=2)
            interpreter.allocate_tensors()
            labels: dict[str, int] = {}
            with self.label_path.open(encoding="utf-8-sig", newline="") as handle:
                for row in csv.DictReader(handle):
                    labels[row["display_name"]] = int(row["index"])
            self._indices = {
                category: [labels[label] for label in config["labels"] if label in labels]
                for category, config in CATEGORIES.items()
            }
            self._interpreter = interpreter

    def _invoke(self, window: np.ndarray) -> np.ndarray:
        assert self._interpreter is not None
        input_info = self._interpreter.get_input_details()[0]
        self._interpreter.set_tensor(input_info["index"], window.astype(input_info["dtype"], copy=False))
        self._interpreter.invoke()
        output = self._interpreter.get_output_details()[0]
        return np.asarray(self._interpreter.get_tensor(output["index"])).reshape(-1)

    def analyze(self, audio_path: Path, _location: str | None = None) -> dict[str, Any]:
        started = time.perf_counter()
        self._load()
        waveform = _read_pcm16_mono(audio_path)
        frames: list[tuple[np.ndarray, float, float]] = []
        with self._inference_lock:
            for offset in range(0, len(waveform), HOP_SAMPLES):
                window = np.zeros(WINDOW_SAMPLES, dtype=np.float32)
                available = min(WINDOW_SAMPLES, len(waveform) - offset)
                window[:available] = waveform[offset : offset + available]
                frames.append(
                    (
                        self._invoke(window),
                        offset / SAMPLE_RATE,
                        (offset + available) / SAMPLE_RATE,
                    )
                )
                if offset + WINDOW_SAMPLES >= len(waveform):
                    break
        detections: list[dict[str, Any]] = []
        for category, config in CATEGORIES.items():
            indices = self._indices.get(category, [])
            scored = [
                (max((float(scores[index]) for index in indices if index < len(scores)), default=0.0), start, end)
                for scores, start, end in frames
            ]
            confidence = max((item[0] for item in scored), default=0.0)
            threshold = float(config["threshold"])
            if confidence < threshold:
                continue
            intervals = [
                {"start": start, "end": end}
                for score, start, end in scored
                if score >= threshold
            ]
            detections.append(
                {
                    "category_id": category,
                    "name_zh": config["name_zh"],
                    "confidence": round(confidence, 4),
                    "model": "YAMNet tflite-1",
                    "intervals": intervals,
                }
            )
        detections.sort(key=lambda item: item["confidence"], reverse=True)
        names = [item["name_zh"] for item in detections]
        primary = names[0] if names else "无法判断"
        evidence = [
            f"YAMNet在{item['intervals'][0]['start']:.1f}–{item['intervals'][0]['end']:.1f}秒检测到{item['name_zh']}线索"
            for item in detections[:3]
            if item["intervals"]
        ]
        result = {
            "sound_types": names or ["无法判断"],
            "primary_sound_type": primary,
            "possible_sound_types": [],
            "dominant_sound": primary,
            "possible_species": [],
            "confidence_level": (
                "high" if detections and detections[0]["confidence"] >= 0.60
                else "medium" if detections
                else "low"
            ),
            "evidence": evidence,
            "uncertainty": "YAMNet只提供通用声景候选，具体物种需要专业模型和现场观察。",
            "model": "YAMNet tflite-1",
            "detections": detections,
            "usage": None,
        }
        log_event(
            logger,
            logging.INFO,
            "yamnet_inference_completed",
            duration_ms=round((time.perf_counter() - started) * 1000),
            detection_count=len(detections),
        )
        return result
