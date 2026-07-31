"""Generate provisional labels and BirdNET target-species flags for stage-1 previews."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import birdnet


TARGET_LABELS = {
    "鹊鸲": "Copsychus saularis_Oriental Magpie-Robin",
    "白头鹎": "Pycnonotus sinensis_Light-vented Bulbul",
    "乌鸫": "Turdus mandarinus_Chinese Blackbird",
    "珠颈斑鸠": "Streptopelia chinensis_Spotted Dove",
    "红嘴蓝鹊": "Urocissa erythroryncha_Red-billed Blue-Magpie",
    "黑水鸡": "Gallinula chloropus_Eurasian Moorhen",
}

CLASS_BY_CATEGORY = {
    "wind_trees": "background_candidate",
    "distant_traffic": "background_candidate",
    "people_footsteps": "background_privacy_review",
    "rain_water_park": "background_candidate",
    "non_target_soundscape": "mixed_or_unknown_candidate",
}

SPEECH_TERMS = {
    "voice", "voices", "speech", "talk", "talking", "conversation", "people",
    "crowd", "mumbling", "children", "child", "man", "woman", "radio", "public-square",
}
CHILD_TERMS = {"children", "child", "kids", "kid", "playground"}
BIRD_TERMS = {"bird", "birds", "birdsong", "crow", "crows", "dove", "bulbul"}


def text_tokens(row: dict[str, str]) -> set[str]:
    text = " ".join((row.get("name", ""), row.get("tags", ""))).lower()
    return set(re.findall(r"[a-z]+(?:-[a-z]+)?", text))


def metadata_label(row: dict[str, str]) -> dict[str, str]:
    tokens = text_tokens(row)
    speech_hits = sorted(tokens & SPEECH_TERMS)
    child_hits = sorted(tokens & CHILD_TERMS)
    bird_hits = sorted(tokens & BIRD_TERMS)
    contains_speech = "possible" if speech_hits or row["category"] == "people_footsteps" else "unlikely"
    privacy_risk = "high" if child_hits else "medium" if contains_speech == "possible" else "low"
    return {
        "provisional_class": CLASS_BY_CATEGORY[row["category"]],
        "contains_speech": contains_speech,
        "privacy_risk": privacy_risk,
        "metadata_speech_terms": "|".join(speech_hits),
        "metadata_bird_terms": "|".join(bird_hits),
        "review_status": "machine_labeled_needs_listening",
        "label_source": "category_title_tags_heuristic",
    }


def format_time(value: Any) -> str:
    if hasattr(value, "total_seconds"):
        return f"{value.total_seconds():.3f}"
    return str(value)


def run_birdnet(paths: list[Path]) -> list[dict[str, Any]]:
    model = birdnet.load("acoustic", "2.4", "tf")
    result = model.predict(
        [str(path) for path in paths],
        custom_species_list=list(TARGET_LABELS.values()),
        top_k=6,
        default_confidence_threshold=0.05,
        n_producers=2,
        n_workers=1,
        batch_size=8,
        prefetch_ratio=2,
        show_stats="minimal",
    )
    return result.to_dataframe().to_dict(orient="records")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({key for row in rows for key in row})
    with path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("data/metadata/freesound_candidates.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/freesound_review_queue.csv"))
    parser.add_argument("--detections", type=Path, default=Path("data/metadata/freesound_birdnet_detections.csv"))
    parser.add_argument("--summary", type=Path, default=Path("data/metadata/freesound_labeling_summary.json"))
    parser.add_argument("--skip-birdnet", action="store_true")
    args = parser.parse_args()

    with args.manifest.open("r", encoding="utf-8-sig", newline="") as handle:
        source_rows = list(csv.DictReader(handle))

    existing_human_labels: dict[str, dict[str, str]] = {}
    if args.output.exists():
        with args.output.open("r", encoding="utf-8-sig", newline="") as handle:
            for existing in csv.DictReader(handle):
                existing_human_labels[existing["freesound_id"]] = {
                    key: value
                    for key, value in existing.items()
                    if key.startswith("human_") or key in {"reviewed_class", "valid_intervals"}
                }

    queue: list[dict[str, Any]] = []
    for row in source_rows:
        machine_row = {
            **row,
            **metadata_label(row),
            "contains_target_species": "unchecked",
            "birdnet_max_confidence": "",
            "birdnet_target_detections": "",
            "human_final_class": "",
            "human_contains_speech": "",
            "human_contains_target_species": "",
            "human_valid_intervals": "",
            "human_reviewer": "",
            "human_reviewed_at": "",
            "human_review_notes": "",
        }
        machine_row.update(existing_human_labels.get(row["freesound_id"], {}))
        if machine_row.get("human_final_class"):
            machine_row["review_status"] = "human_reviewed"
        queue.append(machine_row)

    detection_rows: list[dict[str, Any]] = []
    if not args.skip_birdnet:
        paths = [Path(row["local_path"]).resolve() for row in queue]
        raw_detections = run_birdnet(paths)
        reverse_names = {label: name_zh for name_zh, label in TARGET_LABELS.items()}
        by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)

        for detection in raw_detections:
            input_path = str(Path(str(detection["input"])).resolve())
            species_label = str(detection["species_name"])
            row = {
                "local_path": input_path,
                "freesound_id": next(
                    (item["freesound_id"] for item in queue if str(Path(item["local_path"]).resolve()) == input_path),
                    "",
                ),
                "species_name_zh": reverse_names.get(species_label, ""),
                "species_label": species_label,
                "confidence": round(float(detection["confidence"]), 6),
                "start_time": format_time(detection.get("start_time", "")),
                "end_time": format_time(detection.get("end_time", "")),
            }
            detection_rows.append(row)
            by_path[input_path].append(row)

        for row in queue:
            resolved = str(Path(row["local_path"]).resolve())
            detections = sorted(by_path.get(resolved, []), key=lambda item: float(item["confidence"]), reverse=True)
            max_confidence = max((float(item["confidence"]) for item in detections), default=0.0)
            if max_confidence >= 0.5:
                row["contains_target_species"] = "likely_needs_listening"
            elif max_confidence >= 0.25:
                row["contains_target_species"] = "possible_needs_listening"
            else:
                row["contains_target_species"] = "no_strong_birdnet_evidence"
            row["birdnet_max_confidence"] = round(max_confidence, 6)
            row["birdnet_target_detections"] = "; ".join(
                f"{item['species_name_zh']}:{item['confidence']}@{item['start_time']}-{item['end_time']}"
                for item in detections[:10]
            )
            if row["contains_target_species"] != "no_strong_birdnet_evidence" and row["provisional_class"] == "background_candidate":
                row["provisional_class"] = "mixed_target_review"

    write_csv(args.output, queue)
    write_csv(args.detections, detection_rows)
    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "rows": len(queue),
        "review_status_counts": dict(Counter(row["review_status"] for row in queue)),
        "provisional_class_counts": dict(Counter(row["provisional_class"] for row in queue)),
        "speech_flag_counts": dict(Counter(row["contains_speech"] for row in queue)),
        "privacy_risk_counts": dict(Counter(row["privacy_risk"] for row in queue)),
        "target_species_flag_counts": dict(Counter(row["contains_target_species"] for row in queue)),
        "birdnet_detection_rows": len(detection_rows),
        "warning": "All labels are machine-assisted and require listening confirmation.",
    }
    args.summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"Review queue: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
