from __future__ import annotations

import threading
from pathlib import Path
from typing import Any

import birdnet


SPECIES = {
    "Copsychus saularis_Oriental Magpie-Robin": "鹊鸲",
    "Pycnonotus sinensis_Light-vented Bulbul": "白头鹎",
    "Turdus mandarinus_Chinese Blackbird": "乌鸫",
    "Streptopelia chinensis_Spotted Dove": "珠颈斑鸠",
    "Urocissa erythroryncha_Red-billed Blue-Magpie": "红嘴蓝鹊",
    "Gallinula chloropus_Eurasian Moorhen": "黑水鸡",
}


def _seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


class BirdNetAnalyzer:
    def __init__(self) -> None:
        self._model = None
        self._lock = threading.Lock()

    def _load(self):
        if self._model is None:
            self._model = birdnet.load("acoustic", "2.4", "tf")
        return self._model

    def analyze(self, audio_path: Path) -> dict[str, Any]:
        with self._lock:
            model = self._load()
            rows = model.predict(
                [str(audio_path.resolve())],
                custom_species_list=list(SPECIES),
                top_k=3,
                default_confidence_threshold=0.05,
                n_producers=1,
                n_workers=1,
                batch_size=4,
                prefetch_ratio=1,
                show_stats="minimal",
            ).to_dataframe().to_dict(orient="records")

        best_by_species: dict[str, dict[str, Any]] = {}
        for row in rows:
            label = str(row["species_name"])
            confidence = float(row["confidence"])
            current = best_by_species.get(label)
            if current is None or confidence > current["confidence"]:
                best_by_species[label] = {
                    "name_zh": SPECIES.get(label, label),
                    "label": label,
                    "confidence": round(confidence, 4),
                    "start_seconds": round(_seconds(row["start_time"]), 3),
                    "end_seconds": round(_seconds(row["end_time"]), 3),
                    "status": "likely" if confidence >= 0.5 else "candidate",
                }

        detections = sorted(
            best_by_species.values(), key=lambda item: item["confidence"], reverse=True
        )
        return {
            "model": "BirdNET acoustic 2.4",
            "scope": "杭州MVP六种常见鸟类",
            "detections": detections[:3],
        }
