from __future__ import annotations

import csv
import json
import math
import shutil
import subprocess
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
import tensorflow as tf

from studio_config import (
    BIRD_SPECIES_DISPLAY_THRESHOLD,
    CATEGORY_NAMES,
    LABELS,
    MAX_AUDIO_SECONDS,
    MODELS,
    OBSERVATION_TASKS,
)


@dataclass(frozen=True)
class Interval:
    start: float
    end: float


@dataclass
class Detection:
    category_id: str
    name_zh: str
    confidence: float
    model: str
    intervals: list[Interval]
    species_name: str | None = None
    scientific_name: str | None = None
    tentative: bool = False

    @property
    def key(self) -> str:
        return f"{self.category_id}|{self.scientific_name or self.species_name or ''}"


def _load_audio(path: str | Path) -> tuple[np.ndarray, int]:
    try:
        waveform, sample_rate = sf.read(str(path), dtype="float32", always_2d=True)
    except sf.LibsndfileError:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            raise ValueError("当前运行环境无法解码这种录音格式，请改用 WAV、MP3 或 FLAC。") from None
        with tempfile.TemporaryDirectory(prefix="nature-audio-") as folder:
            decoded = Path(folder) / "decoded.wav"
            completed = subprocess.run(
                [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(path), "-t", str(MAX_AUDIO_SECONDS), "-ac", "1", "-ar", "48000", "-c:a", "pcm_s16le", str(decoded)],
                capture_output=True,
                text=True,
                timeout=45,
            )
            if completed.returncode != 0 or not decoded.is_file():
                raise ValueError("录音格式无法解码，请换一种格式后重试。") from None
            waveform, sample_rate = sf.read(str(decoded), dtype="float32", always_2d=True)
    mono = waveform.mean(axis=1)
    mono = mono[: int(sample_rate * MAX_AUDIO_SECONDS)]
    if not mono.size:
        raise ValueError("没有读取到有效声音，请重新录制。")
    peak = float(np.max(np.abs(mono)))
    if peak > 1.0:
        mono = mono / peak
    return np.ascontiguousarray(mono, dtype=np.float32), int(sample_rate)


def _resample(waveform: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    if source_rate == target_rate:
        return waveform
    divisor = math.gcd(source_rate, target_rate)
    return np.ascontiguousarray(
        resample_poly(waveform, target_rate // divisor, source_rate // divisor),
        dtype=np.float32,
    )


def _windows(waveform: np.ndarray, size: int, hop: int) -> list[tuple[np.ndarray, Interval]]:
    result: list[tuple[np.ndarray, Interval]] = []
    rate = 16_000 if size == 15_600 else 48_000
    for offset in range(0, len(waveform), hop):
        window = np.zeros(size, dtype=np.float32)
        available = min(size, len(waveform) - offset)
        window[:available] = waveform[offset : offset + available]
        result.append((window, Interval(offset / rate, (offset + available) / rate)))
        if offset + size >= len(waveform):
            break
    return result


def _sigmoid(values: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.clip(values, -40, 40)))


def _cosine(left: np.ndarray, right: list[float]) -> float:
    if len(left) != len(right):
        return 1.0
    right_array = np.asarray(right, dtype=np.float32)
    denominator = float(np.linalg.norm(left) * np.linalg.norm(right_array))
    return float(np.dot(left, right_array) / denominator) if denominator else -1.0


class StudioAnalyzer:
    """Python equivalent of the Android TFLite candidate pipeline."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._inference_lock = threading.Lock()
        self._loaded = False

    def _load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            self.yamnet = tf.lite.Interpreter(model_path=str(MODELS / "yamnet.tflite"), num_threads=2)
            self.birdnet = tf.lite.Interpreter(model_path=str(MODELS / "birdnet.tflite"), num_threads=2)
            self.nonbird = tf.lite.Interpreter(model_path=str(MODELS / "nonbird.tflite"), num_threads=2)
            for interpreter in (self.yamnet, self.birdnet, self.nonbird):
                interpreter.allocate_tensors()
            self.yamnet_groups = self._load_yamnet_groups()
            self.birds = json.loads((LABELS / "birdnet_hz.json").read_text(encoding="utf-8"))["species"]
            metadata = json.loads((MODELS / "nonbird.json").read_text(encoding="utf-8"))
            self.nonbird_classes = metadata["classes"]
            self.nonbird_rejection = metadata["rejection"]
            self._loaded = True

    @staticmethod
    def _load_yamnet_groups() -> dict[str, dict[str, Any]]:
        aliases = {
            "bird": ("Bird", "Bird vocalization", "Chirp, tweet"),
            "frog": ("Frog", "Croak"),
            "insect": ("Insect", "Cricket", "Cicada"),
            "rain": ("Rain", "Raindrop"),
            "water": ("Water", "Stream", "Waterfall"),
            "wind": ("Wind", "Rustling leaves"),
            "human": ("Speech", "Child speech", "Conversation"),
            "footsteps": ("Walk, footsteps", "Run"),
            "traffic": ("Traffic noise, roadway noise", "Vehicle", "Engine"),
        }
        thresholds = {key: 0.15 for key in aliases}
        thresholds.update({"bird": 0.12, "frog": 0.12, "insect": 0.12, "human": 0.20})
        labels: dict[str, int] = {}
        with (LABELS / "yamnet.csv").open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                labels[row["display_name"]] = int(row["index"])
        return {
            key: {"indices": [labels[name] for name in names if name in labels], "threshold": thresholds[key]}
            for key, names in aliases.items()
        }

    @staticmethod
    def _invoke(interpreter: tf.lite.Interpreter, value: np.ndarray) -> list[np.ndarray]:
        input_info = interpreter.get_input_details()[0]
        wanted = list(value.shape)
        if input_info["shape"].tolist() != wanted:
            interpreter.resize_tensor_input(input_info["index"], wanted)
            interpreter.allocate_tensors()
            input_info = interpreter.get_input_details()[0]
        interpreter.set_tensor(input_info["index"], value.astype(input_info["dtype"], copy=False))
        interpreter.invoke()
        return [np.asarray(interpreter.get_tensor(item["index"])) for item in interpreter.get_output_details()]

    def _yamnet(self, waveform: np.ndarray, sample_rate: int) -> list[Detection]:
        audio = _resample(waveform, sample_rate, 16_000)
        frame_values: list[tuple[np.ndarray, Interval]] = []
        for window, interval in _windows(audio, 15_600, 7_800):
            scores = self._invoke(self.yamnet, window)[0].reshape(-1)
            frame_values.append((scores, interval))
        detections: list[Detection] = []
        for category, config in self.yamnet_groups.items():
            values = [max((float(scores[i]) for i in config["indices"] if i < len(scores)), default=0.0) for scores, _ in frame_values]
            confidence = max(values, default=0.0)
            if confidence < config["threshold"]:
                continue
            active = [frame_values[i][1] for i, value in enumerate(values) if value >= config["threshold"]]
            detections.append(Detection(category, CATEGORY_NAMES[category], confidence, "YAMNet tflite-1", active))
        return detections

    def _birdnet_and_nonbird(self, waveform: np.ndarray, sample_rate: int) -> tuple[list[Detection], list[Detection]]:
        audio = _resample(waveform, sample_rate, 48_000)
        bird_best: dict[int, tuple[float, list[Interval]]] = {}
        embedding_windows: list[tuple[np.ndarray, Interval]] = []
        for window, interval in _windows(audio, 144_000, 144_000):
            outputs = self._invoke(self.birdnet, window[None, :])
            scores = _sigmoid(outputs[0]).reshape(-1)
            embedding = outputs[1].reshape(-1).astype(np.float32)
            embedding_windows.append((embedding, interval))
            for item in self.birds:
                index = int(item["output_index"])
                confidence = float(scores[index])
                if confidence < 0.05:
                    continue
                current = bird_best.get(index)
                if current is None:
                    bird_best[index] = (confidence, [interval])
                else:
                    current[1].append(interval)
                    bird_best[index] = (max(current[0], confidence), current[1])
        by_index = {int(item["output_index"]): item for item in self.birds}
        birds = [
            Detection("bird", "鸟类鸣叫", score, "BirdNET 2.4 FP16", intervals, item["name_zh"], item.get("scientific_name"))
            for index, (score, intervals) in bird_best.items()
            for item in [by_index[index]]
        ]
        birds.sort(key=lambda item: item.confidence, reverse=True)

        nonbirds: list[Detection] = []
        class_items = [item for item in self.nonbird_classes if item["taxon_id"] != "background"]
        background = next((item for item in self.nonbird_classes if item["taxon_id"] == "background"), None)
        for item in class_items:
            accepted: list[tuple[float, Interval]] = []
            for embedding, interval in embedding_windows:
                probabilities = _sigmoid(self._invoke(self.nonbird, embedding[None, :])[0]).reshape(-1)
                index = int(item["output_index"])
                probability = float(probabilities[index])
                background_probability = float(probabilities[int(background["output_index"])]) if background else 0.0
                runner_up = max((float(probabilities[int(other["output_index"])]) for other in class_items if other is not item), default=0.0)
                if probability < float(item["threshold"]):
                    continue
                if probability - background_probability < float(self.nonbird_rejection["background_margin"]):
                    continue
                if probability - runner_up < float(self.nonbird_rejection.get("min_top_margin", 0.0)):
                    continue
                if _cosine(embedding, item["centroid"]) < float(item["min_cosine_similarity"]):
                    continue
                accepted.append((probability, interval))
            minimum = int(self.nonbird_rejection["min_supporting_windows"])
            excess = float(self.nonbird_rejection["short_clip_threshold_excess"])
            if len(accepted) < minimum and not (len(accepted) == 1 and accepted[0][0] >= float(item["threshold"]) + excess):
                continue
            if accepted:
                nonbirds.append(Detection(item["category_id"], CATEGORY_NAMES[item["category_id"]], max(x[0] for x in accepted), "自然声探员 Non-bird 0.1", [x[1] for x in accepted], item["name_zh"], item.get("scientific_name")))
        nonbirds.sort(key=lambda item: item.confidence, reverse=True)
        return birds[:3], nonbirds

    @staticmethod
    def _overlap(left: list[Interval], right: list[Interval]) -> bool:
        if not left or not right:
            return True
        return any(min(a.end, b.end) - max(a.start, b.start) > 0.1 for a in left for b in right)

    def _fuse(self, generic: list[Detection], birds: list[Detection], nonbirds: list[Detection]) -> list[Detection]:
        generic_by_category = {item.category_id: item for item in generic}
        result: list[Detection] = []
        for bird in birds:
            support = generic_by_category.get("bird")
            supported = support is not None and self._overlap(bird.intervals, support.intervals)
            if bird.confidence >= BIRD_SPECIES_DISPLAY_THRESHOLD:
                bird.confidence = min(1.0, bird.confidence + (0.04 if supported else 0.0))
                result.append(bird)
            elif (supported and bird.confidence >= 0.05) or bird.confidence >= 0.08:
                bird.tentative = True
                result.append(bird)
        for item in nonbirds:
            support = generic_by_category.get(item.category_id)
            supported = support is not None and self._overlap(item.intervals, support.intervals)
            if item.confidence >= 0.65 or (supported and item.confidence >= 0.35):
                item.confidence = min(1.0, item.confidence + (0.04 if supported else 0.0))
                result.append(item)
        covered = {item.category_id for item in result}
        result.extend(item for item in generic if item.category_id not in covered and item.category_id != "bird")
        if not any(item.category_id == "bird" for item in result) and "bird" in generic_by_category:
            result.append(generic_by_category["bird"])
        result.sort(key=lambda item: item.confidence + (0.03 if item.species_name else 0) - (0.05 if item.tentative else 0), reverse=True)
        birds_out = [item for item in result if item.category_id == "bird"][:3]
        general_out = [item for item in result if item.category_id != "bird"][:4]
        return sorted([*birds_out, *general_out], key=lambda item: item.confidence, reverse=True)

    def analyze(self, audio_path: str | Path) -> dict[str, Any]:
        self._load()
        waveform, sample_rate = _load_audio(audio_path)
        # TFLite Interpreter mutates shared tensor state during invoke(). Keep one
        # request inside the model pipeline at a time when the Studio uses the
        # process-wide analyzer instance.
        with self._inference_lock:
            generic = self._yamnet(waveform, sample_rate)
            birds, nonbirds = self._birdnet_and_nonbird(waveform, sample_rate)
            detections = self._fuse(generic, birds, nonbirds)
        duration = len(waveform) / sample_rate
        return {
            "duration": round(duration, 2),
            "detections": detections,
            "observation": OBSERVATION_TASKS.get(detections[0].category_id, "再听一次，并记录声音出现的时间、方向和周围环境。") if detections else "这段录音的线索还不够清楚，换一个更安静的位置再录一次。",
            "quality": "声音偏轻，建议靠近目标声源后再录。" if float(np.sqrt(np.mean(waveform ** 2))) < 0.008 else "录音音量可用于候选分析。",
        }


ANALYZER = StudioAnalyzer()
