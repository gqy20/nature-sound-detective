"""Evaluate BirdNET on deterministic mixtures of labelled bird recordings.

This is a controlled stress test, not a real-world accuracy claim.  It selects the
strongest known three-second window for each mapped challenge species, creates
repeatable two/three-species mixtures, and measures whether every expected species
survives the same confidence threshold and top-three truncation used by the app.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import time
from typing import Any
import wave

import birdnet
import numpy as np


SAMPLE_RATE = 48_000
WINDOW_SECONDS = 3.0
WINDOW_SAMPLES = int(SAMPLE_RATE * WINDOW_SECONDS)


def read_pcm16_mono(path: Path, start_seconds: float, duration_seconds: float = WINDOW_SECONDS) -> np.ndarray:
    """Read a fixed-size mono PCM16 segment, padding the end with silence."""
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise ValueError(f"Expected mono PCM16 WAV: {path}")
        if handle.getframerate() != SAMPLE_RATE:
            raise ValueError(f"Expected {SAMPLE_RATE} Hz WAV: {path}")
        handle.setpos(min(int(start_seconds * SAMPLE_RATE), handle.getnframes()))
        raw = handle.readframes(int(duration_seconds * SAMPLE_RATE))
    samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    target_length = int(duration_seconds * SAMPLE_RATE)
    return np.pad(samples, (0, max(0, target_length - len(samples))))[:target_length]


def prepare_track(samples: np.ndarray, target_rms: float = 0.12) -> np.ndarray:
    """Remove DC, RMS-normalize and apply a short edge fade."""
    track = samples.astype(np.float32, copy=True)
    track -= float(np.mean(track))
    rms = float(np.sqrt(np.mean(np.square(track))))
    if rms < 1e-6:
        raise ValueError("Cannot mix a silent reference segment")
    track *= target_rms / rms
    fade_samples = min(int(SAMPLE_RATE * 0.01), len(track) // 2)
    if fade_samples:
        fade = np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
        track[:fade_samples] *= fade
        track[-fade_samples:] *= fade[::-1]
    return track


def mix_tracks(tracks: list[np.ndarray], gains_db: list[float], sequential: bool = False) -> np.ndarray:
    if len(tracks) != len(gains_db) or not tracks:
        raise ValueError("tracks and gains_db must be non-empty and the same size")
    adjusted = [track * (10.0 ** (gain / 20.0)) for track, gain in zip(tracks, gains_db)]
    mixed = np.concatenate(adjusted) if sequential else np.sum(np.stack(adjusted), axis=0)
    peak = float(np.max(np.abs(mixed)))
    if peak > 0.98:
        mixed *= 0.98 / peak
    return mixed.astype(np.float32)


def write_pcm16_mono(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    raw = (pcm * 32767.0).round().astype("<i2").tobytes()
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(raw)


def load_expected_labels(catalog_path: Path, labels_path: Path) -> dict[str, str]:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))["classes"]
    labels = json.loads(labels_path.read_text(encoding="utf-8"))["species"]
    label_by_scientific = {
        str(row["scientific_name"]): f"{row['scientific_name']}_{row['name_en']}" for row in labels
    }
    return {
        str(row["name_zh"]): label_by_scientific[str(row["birdnet_scientific_name"])]
        for row in catalog
        if row["category_id"] == "bird"
        and row.get("birdnet_scientific_name") in label_by_scientific
    }


def load_candidate_labels(labels_path: Path) -> tuple[list[str], dict[str, str]]:
    """Load the complete geographic candidate set used by the mobile app."""
    labels = json.loads(labels_path.read_text(encoding="utf-8"))["species"]
    candidates = [f"{row['scientific_name']}_{row['name_en']}" for row in labels]
    names = {
        f"{row['scientific_name']}_{row['name_en']}": str(row["name_zh"])
        for row in labels
    }
    return candidates, names


def load_reference_segments(
    detections_path: Path, standard_root: Path, expected_labels: dict[str, str]
) -> dict[str, dict[str, Any]]:
    """Choose the highest-confidence expected window for every mapped species."""
    best: dict[str, dict[str, Any]] = {}
    with detections_path.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            name = str(row["expected_name_zh"])
            if name not in expected_labels or str(row["is_expected"]).lower() != "true":
                continue
            confidence = float(row["confidence"])
            if name not in best or confidence > float(best[name]["confidence"]):
                best[name] = {
                    "path": standard_root / Path(row["source_path"]),
                    "start_seconds": float(row["start_seconds"]),
                    "confidence": confidence,
                }
    missing = sorted(set(expected_labels) - set(best))
    if missing:
        raise ValueError(f"No reference detection for: {', '.join(missing)}")
    for name, reference in best.items():
        if not Path(reference["path"]).is_file():
            raise FileNotFoundError(f"Missing reference WAV for {name}: {reference['path']}")
    return best


def build_scenarios(species: list[str]) -> list[dict[str, Any]]:
    """Build a deterministic, balanced matrix where each species has every role."""
    scenarios: list[dict[str, Any]] = []
    for index, primary in enumerate(species):
        secondary = species[(index + 1) % len(species)]
        third = species[(index + 4) % len(species)]
        for scenario, gains_db, sequential in (
            ("overlap_equal", [0.0, 0.0], False),
            ("overlap_secondary_minus_6db", [0.0, -6.0], False),
            ("overlap_secondary_minus_12db", [0.0, -12.0], False),
            ("sequential_equal", [0.0, 0.0], True),
        ):
            scenarios.append(
                {
                    "scenario": scenario,
                    "species": [primary, secondary],
                    "gains_db": gains_db,
                    "sequential": sequential,
                }
            )
        scenarios.append(
            {
                "scenario": "overlap_three_equal",
                "species": [primary, secondary, third],
                "gains_db": [0.0, 0.0, 0.0],
                "sequential": False,
            }
        )
    return scenarios


def seconds(value: Any) -> float:
    return float(value.total_seconds()) if hasattr(value, "total_seconds") else float(value)


def aggregate_predictions(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Mirror the app: keep each species' maximum window score, then rank."""
    best: dict[str, dict[str, Any]] = {}
    for row in rows:
        label = str(row["species_name"])
        score = float(row["confidence"])
        if label not in best or score > float(best[label]["confidence"]):
            best[label] = {
                "label": label,
                "confidence": score,
                "start_seconds": seconds(row["start_time"]),
                "end_seconds": seconds(row["end_time"]),
            }
    return sorted(best.values(), key=lambda row: float(row["confidence"]), reverse=True)


def score_clip(expected_labels: list[str], ranked: list[dict[str, Any]], threshold: float) -> dict[str, Any]:
    displayed = [row for row in ranked if float(row["confidence"]) >= threshold][:3]
    displayed_labels = [str(row["label"]) for row in displayed]
    expected_set = set(expected_labels)
    hits = expected_set.intersection(displayed_labels)
    expected_details = []
    for label in expected_labels:
        row = next((item for item in ranked if item["label"] == label), None)
        rank = next((i for i, item in enumerate(ranked, 1) if item["label"] == label), None)
        expected_details.append(
            {
                "label": label,
                "confidence": round(float(row["confidence"]), 6) if row else 0.0,
                "rank": rank,
                "displayed": label in displayed_labels,
            }
        )
    return {
        "expected_count": len(expected_labels),
        "hit_count": len(hits),
        "all_expected_displayed": len(hits) == len(expected_set),
        "false_positive_count": len(set(displayed_labels) - expected_set),
        "displayed": [
            {"label": row["label"], "confidence": round(float(row["confidence"]), 6)}
            for row in displayed
        ],
        "expected": expected_details,
    }


def summarize(results: list[dict[str, Any]], threshold: float) -> dict[str, Any]:
    expected_total = sum(int(row["score"]["expected_count"]) for row in results)
    hit_total = sum(int(row["score"]["hit_count"]) for row in results)
    clip_total = len(results)
    role_totals = [0, 0, 0]
    role_hits = [0, 0, 0]
    for row in results:
        for index, expected in enumerate(row["score"]["expected"]):
            role_totals[index] += 1
            role_hits[index] += int(expected["displayed"])
    return {
        "clip_count": clip_total,
        "expected_label_count": expected_total,
        "display_threshold": threshold,
        "top_3_label_recall": round(hit_total / expected_total, 4),
        "complete_clip_rate": round(
            sum(bool(row["score"]["all_expected_displayed"]) for row in results) / clip_total, 4
        ),
        "mean_false_positives_per_clip": round(
            sum(int(row["score"]["false_positive_count"]) for row in results) / clip_total, 4
        ),
        "role_recall": {
            f"species_{index + 1}": round(role_hits[index] / total, 4) if total else None
            for index, total in enumerate(role_totals)
        },
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0]) if rows else ["empty"]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run deterministic multi-bird mixture evaluation")
    parser.add_argument("--standard-root", type=Path, default=Path("data/interim/challenge_2026_standard_48k"))
    parser.add_argument("--standard-detections", type=Path, default=Path("data/metadata/challenge_2026_birdnet_standard_detections.csv"))
    parser.add_argument("--catalog", type=Path, default=Path("ml/configs/challenge_2026_species.json"))
    parser.add_argument("--birdnet-labels", type=Path, default=Path("mobile/assets/labels/birdnet_hz.json"))
    parser.add_argument("--mixture-root", type=Path, default=Path("data/interim/challenge_2026_multibird_mixtures"))
    parser.add_argument("--detections", type=Path, default=Path("data/metadata/challenge_2026_multibird_detections.csv"))
    parser.add_argument("--report", type=Path, default=Path("data/metadata/challenge_2026_multibird_report.json"))
    parser.add_argument("--threshold", type=float, default=0.05)
    args = parser.parse_args()

    expected_labels = load_expected_labels(args.catalog, args.birdnet_labels)
    candidate_labels, name_by_label = load_candidate_labels(args.birdnet_labels)
    references = load_reference_segments(args.standard_detections, args.standard_root, expected_labels)
    species = sorted(references)
    prepared = {
        name: prepare_track(read_pcm16_mono(Path(reference["path"]), float(reference["start_seconds"])))
        for name, reference in references.items()
    }
    scenarios = build_scenarios(species)
    manifests: list[dict[str, Any]] = []
    for index, scenario in enumerate(scenarios, 1):
        slug = "__".join(scenario["species"])
        output = args.mixture_root / scenario["scenario"] / f"{index:03d}__{slug}.wav"
        mixture = mix_tracks(
            [prepared[name] for name in scenario["species"]],
            scenario["gains_db"],
            sequential=bool(scenario["sequential"]),
        )
        write_pcm16_mono(output, mixture)
        manifests.append(scenario | {"path": output})

    started = time.perf_counter()
    model = birdnet.load("acoustic", "2.4", "tf")
    raw_predictions = model.predict(
        [str(row["path"].resolve()) for row in manifests],
        custom_species_list=candidate_labels,
        # Retain every geographic candidate above the raw threshold so that
        # cross-window max aggregation exactly precedes the final top-three cut.
        top_k=len(candidate_labels),
        default_confidence_threshold=0.01,
        n_producers=1,
        n_workers=1,
        batch_size=8,
        prefetch_ratio=1,
        show_stats="minimal",
    ).to_dataframe().to_dict(orient="records")
    elapsed = time.perf_counter() - started
    by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in raw_predictions:
        by_path[str(Path(str(row["input"])).resolve())].append(row)

    result_rows: list[dict[str, Any]] = []
    detection_rows: list[dict[str, Any]] = []
    for manifest in manifests:
        path = str(manifest["path"].resolve())
        ranked = aggregate_predictions(by_path[path])
        score = score_clip([expected_labels[name] for name in manifest["species"]], ranked, args.threshold)
        result_rows.append(
            {
                "path": manifest["path"].as_posix(),
                "scenario": manifest["scenario"],
                "species": manifest["species"],
                "gains_db": manifest["gains_db"],
                "score": score,
            }
        )
        for rank, candidate in enumerate(ranked, 1):
            detection_rows.append(
                {
                    "mixture_path": manifest["path"].as_posix(),
                    "scenario": manifest["scenario"],
                    "expected_species_zh": "|".join(manifest["species"]),
                    "candidate_species_zh": name_by_label.get(str(candidate["label"]), ""),
                    "candidate_birdnet_label": candidate["label"],
                    "confidence": round(float(candidate["confidence"]), 6),
                    "rank": rank,
                    "is_expected": candidate["label"] in {expected_labels[name] for name in manifest["species"]},
                    "displayed": rank <= 3 and float(candidate["confidence"]) >= args.threshold,
                }
            )

    by_scenario = {
        scenario: summarize([row for row in result_rows if row["scenario"] == scenario], args.threshold)
        for scenario in sorted({str(row["scenario"]) for row in result_rows})
    }
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "evaluation": "BirdNET 2.4 deterministic synthetic multi-bird stress test",
        "warning": "Synthetic mixtures of organizer-provided reference windows; not a substitute for human-labelled wild soundscapes.",
        "method": {
            "sample_rate": SAMPLE_RATE,
            "reference_window_seconds": WINDOW_SECONDS,
            "reference_selection": "highest expected-species confidence window from the standard baseline",
            "track_normalization": "DC removal, RMS 0.12, 10 ms edge fade",
            "ranking": "maximum confidence per species across windows, threshold then top 3",
            "candidate_species_count": len(candidate_labels),
            "mapped_species": species,
        },
        "runtime_seconds": round(elapsed, 3),
        "summary": summarize(result_rows, args.threshold),
        "by_scenario": by_scenario,
        "results": result_rows,
    }
    write_csv(args.detections, detection_rows)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"summary": report["summary"], "by_scenario": by_scenario}, ensure_ascii=False, indent=2))
    print(f"Report: {args.report.resolve()}")


if __name__ == "__main__":
    main()
