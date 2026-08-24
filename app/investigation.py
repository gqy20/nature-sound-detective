from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


SCHEMA_VERSION = 1
OBSERVATION_CHOICES = {"observed", "not_observed", "unknown"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _candidate_id(item: dict[str, Any], index: int) -> str:
    species = item.get("specific_species") or {}
    return str(
        species.get("taxonomy_id")
        or species.get("scientific_name")
        or species.get("name_zh")
        or item.get("category_id")
        or f"candidate-{index + 1}"
    )


def build_evidence_bundle(result: dict[str, Any], location: str) -> dict[str, Any]:
    """Normalize model output into the shared CLI/API investigation evidence contract."""
    candidates: list[dict[str, Any]] = []
    segments: list[dict[str, Any]] = []
    for index, raw in enumerate(result.get("detections") or []):
        item = raw if isinstance(raw, dict) else {}
        candidate_id = _candidate_id(item, index)
        intervals = item.get("intervals") if isinstance(item.get("intervals"), list) else []
        normalized_intervals: list[dict[str, float]] = []
        for interval in intervals:
            if not isinstance(interval, dict):
                continue
            start = float(interval.get("start", 0) or 0)
            end = float(interval.get("end", start) or start)
            normalized = {"start": start, "end": max(start, end)}
            normalized_intervals.append(normalized)
            segments.append({**normalized, "candidate_id": candidate_id})
        species = item.get("specific_species") if isinstance(item.get("specific_species"), dict) else {}
        candidates.append(
            {
                "id": candidate_id,
                "category_id": item.get("category_id", "unknown"),
                "name_zh": species.get("name_zh") or item.get("name_zh") or "待确认声音",
                "scientific_name": species.get("scientific_name"),
                "confidence": float(item.get("confidence", 0) or 0),
                "model": item.get("model"),
                "intervals": normalized_intervals,
                "status": "candidate",
            }
        )
    candidates.sort(key=lambda item: item["confidence"], reverse=True)
    segments.sort(key=lambda item: (item["start"], item["end"], item["candidate_id"]))
    return {
        "schema_version": SCHEMA_VERSION,
        "location": location,
        "primary_sound_type": result.get("primary_sound_type", "无法判断"),
        "scene_clues": list(result.get("detected_sound_types") or result.get("sound_types") or []),
        "possible_scene_clues": list(result.get("possible_sound_types") or []),
        "confidence_level": result.get("confidence_level", "low"),
        "segments": segments,
        "candidates": candidates,
        "model_evidence": list(result.get("evidence") or []),
        "uncertainty": str(result.get("uncertainty") or ""),
        "models": deepcopy(result.get("models") or {}),
    }


def build_investigation(
    result: dict[str, Any],
    location: str,
    *,
    investigation_id: str | None = None,
    created_at: str | None = None,
) -> dict[str, Any]:
    """Create the investigation state used by both real jobs and the CLI."""
    timestamp = created_at or _now()
    card = result.get("card") if isinstance(result.get("card"), dict) else {}
    return {
        "schema_version": SCHEMA_VERSION,
        "id": investigation_id or uuid4().hex,
        "status": "awaiting_observation",
        "round": 0,
        "created_at": timestamp,
        "updated_at": timestamp,
        "evidence": build_evidence_bundle(result, location),
        "question": {
            "id": "field-observation-1",
            "type": "single_choice",
            "text": str(card.get("question") or "安静听一听，你观察到这个声音的特点了吗？"),
            "options": [
                {"value": "observed", "label": "观察到了"},
                {"value": "not_observed", "label": "没有观察到"},
                {"value": "unknown", "label": "无法判断"},
            ],
            "purpose": "补充AI无法从录音中获得的现场证据",
        },
        "observations": [],
        "decision_history": [
            {
                "at": timestamp,
                "event": "investigation_created",
                "status": "awaiting_observation",
                "reason": "模型候选已经生成，等待至少一项现场观察",
            }
        ],
        "stop_reason": None,
    }


def apply_observation(
    investigation: dict[str, Any],
    *,
    question_id: str,
    choice: str,
    note: str = "",
    source: str = "user",
    observed_at: str | None = None,
) -> dict[str, Any]:
    """Apply one bounded human observation with deterministic state transitions."""
    if investigation.get("status") != "awaiting_observation":
        raise ValueError("这次调查已经结案，不能继续提交观察")
    question = investigation.get("question") or {}
    if question_id != question.get("id"):
        raise ValueError("观察问题与当前调查不一致")
    normalized_choice = choice.strip().lower()
    if normalized_choice not in OBSERVATION_CHOICES:
        raise ValueError("观察选项无效")
    clean_note = note.strip()
    if len(clean_note) > 300:
        raise ValueError("观察补充不能超过300字")
    timestamp = observed_at or _now()
    updated = deepcopy(investigation)
    updated["round"] = int(updated.get("round", 0)) + 1
    updated["updated_at"] = timestamp
    updated.setdefault("observations", []).append(
        {
            "question_id": question_id,
            "choice": normalized_choice,
            "note": clean_note,
            "source": source,
            "observed_at": timestamp,
        }
    )
    if normalized_choice == "unknown":
        updated["status"] = "unresolved"
        updated["stop_reason"] = "human_could_not_determine"
        reason = "现场暂时无法判断，保留机器候选和不确定性"
    else:
        updated["status"] = "completed"
        updated["stop_reason"] = "human_observation_recorded"
        reason = "已记录一项现场人类证据，调查可以结案"
    updated.setdefault("decision_history", []).append(
        {
            "at": timestamp,
            "event": "observation_applied",
            "status": updated["status"],
            "reason": reason,
            "choice": normalized_choice,
        }
    )
    return updated


def replay_investigation(package: dict[str, Any]) -> dict[str, Any]:
    """Rebuild an investigation from saved model output and observation events."""
    manifest = package.get("run") if isinstance(package.get("run"), dict) else {}
    result = package.get("result") if isinstance(package.get("result"), dict) else {}
    original = package.get("investigation") if isinstance(package.get("investigation"), dict) else {}
    rebuilt = build_investigation(
        result,
        str(manifest.get("location") or original.get("evidence", {}).get("location") or "杭州"),
        investigation_id=str(original.get("id") or manifest.get("run_id") or uuid4().hex),
        created_at=str(original.get("created_at") or manifest.get("created_at") or _now()),
    )
    for observation in original.get("observations") or []:
        rebuilt = apply_observation(
            rebuilt,
            question_id=str(observation.get("question_id") or rebuilt["question"]["id"]),
            choice=str(observation.get("choice") or "unknown"),
            note=str(observation.get("note") or ""),
            source=str(observation.get("source") or "replay"),
            observed_at=str(observation.get("observed_at") or _now()),
        )
    return rebuilt
