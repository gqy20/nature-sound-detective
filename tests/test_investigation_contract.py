from __future__ import annotations

import json
from pathlib import Path

from fastapi.testclient import TestClient

import app.jobs as jobs_module
import app.main as main_module
from app.cli import main as cli_main
from app.investigation import apply_observation, build_investigation, replay_investigation
from app.jobs import JobStore
from app.run_artifacts import load_run_package, sanitize, write_run_package


RESULT = {
    "primary_sound_type": "鸟类鸣叫",
    "sound_types": ["鸟类鸣叫"],
    "detected_sound_types": ["鸟类鸣叫", "风和树叶"],
    "possible_sound_types": ["风和树叶"],
    "confidence_level": "medium",
    "evidence": ["第4至7秒出现重复短鸣"],
    "uncertainty": "具体物种仍待现场观察",
    "models": {"general_audio": "yamnet-test", "bird_species": "birdnet-test"},
    "detections": [
        {
            "category_id": "bird",
            "name_zh": "鸟类鸣叫",
            "confidence": 0.72,
            "model": "birdnet-test",
            "intervals": [{"start": 4.0, "end": 7.0}],
            "specific_species": {
                "name_zh": "白头鹎",
                "scientific_name": "Pycnonotus sinensis",
            },
        }
    ],
    "card": {"question": "声音主要来自高处树冠吗？"},
}

ROOT = Path(__file__).resolve().parents[1]


def test_shared_investigation_contract_is_deterministic():
    first = build_investigation(
        RESULT,
        "杭州植物园",
        investigation_id="same-id",
        created_at="2026-08-24T00:00:00+00:00",
    )
    second = build_investigation(
        RESULT,
        "杭州植物园",
        investigation_id="same-id",
        created_at="2026-08-24T00:00:00+00:00",
    )
    assert first == second
    assert first["evidence"]["candidates"][0]["name_zh"] == "白头鹎"
    assert first["evidence"]["segments"] == [
        {"start": 4.0, "end": 7.0, "candidate_id": "Pycnonotus sinensis"}
    ]


def test_job_store_and_cli_use_the_same_observation_transition(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    initial = build_investigation(
        RESULT,
        "杭州",
        investigation_id="job-shared",
        created_at="2026-08-24T00:00:00+00:00",
    )
    store._jobs["shared"] = {
        "id": "shared",
        "status": "completed",
        "location": "杭州",
        "result": RESULT,
        "investigation": initial,
        "audio_path": str(tmp_path / "audio.wav"),
        "creation": {"status": "idle"},
    }
    try:
        api_result = store.submit_observation(
            "shared",
            question_id="field-observation-1",
            choice="observed",
            note="来自高处树冠",
            source="api",
        )["investigation"]
        cli_result = apply_observation(
            initial,
            question_id="field-observation-1",
            choice="observed",
            note="来自高处树冠",
            source="cli",
            observed_at=api_result["observations"][0]["observed_at"],
        )
        assert api_result["status"] == cli_result["status"] == "completed"
        assert api_result["round"] == cli_result["round"] == 1
        assert api_result["stop_reason"] == cli_result["stop_reason"]
        assert api_result["observations"][0]["choice"] == cli_result["observations"][0]["choice"]
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)


def test_real_api_endpoint_exposes_shared_investigation_state(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    store._jobs["api-job"] = {
        "id": "api-job",
        "status": "completed",
        "location": "杭州",
        "result": RESULT,
        "investigation": build_investigation(RESULT, "杭州", investigation_id="job-api-job"),
        "audio_path": str(tmp_path / "audio.wav"),
        "creation": {"status": "idle"},
    }
    monkeypatch.setattr(main_module, "jobs", store)
    try:
        response = TestClient(main_module.app).post(
            "/api/jobs/api-job/investigation/observations",
            json={
                "question_id": "field-observation-1",
                "choice": "unknown",
                "note": "没有看清",
            },
        )
        assert response.status_code == 200
        investigation = response.json()["investigation"]
        assert investigation["status"] == "unresolved"
        assert investigation["stop_reason"] == "human_could_not_determine"
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)


def test_cli_run_package_can_be_observed_and_replayed(tmp_path):
    investigation = build_investigation(
        RESULT,
        "杭州",
        investigation_id="cli-run",
        created_at="2026-08-24T00:00:00+00:00",
    )
    run_dir = write_run_package(
        tmp_path,
        run={
            "schema_version": 1,
            "run_id": "cli-run",
            "created_at": "2026-08-24T00:00:00+00:00",
            "location": "杭州",
            "mode": "test",
        },
        result=RESULT,
        investigation=investigation,
    )
    assert cli_main(
        [
            "investigate",
            str(run_dir),
            "--choice",
            "observed",
            "--note",
            "来自树冠",
            "--json",
        ]
    ) == 0
    package = load_run_package(run_dir)
    assert package["investigation"]["status"] == "completed"
    replayed = replay_investigation(package)
    assert replayed["status"] == "completed"
    assert cli_main(["replay", str(run_dir), "--json"]) == 0
    replay_report = json.loads((run_dir / "replayed-investigation.json").read_text(encoding="utf-8"))
    assert replay_report["evidence"] == package["investigation"]["evidence"]


def test_run_package_redacts_secrets_but_keeps_model_usage():
    payload = sanitize(
        {
            "api_key": "secret-value",
            "access_token": "secret-token",
            "usage": {"prompt_tokens": 120, "completion_tokens": 35},
        }
    )
    assert payload["api_key"] == "[REDACTED]"
    assert payload["access_token"] == "[REDACTED]"
    assert payload["usage"] == {"prompt_tokens": 120, "completion_tokens": 35}


def test_web_uses_server_investigation_contract_instead_of_local_state_rules():
    html = (ROOT / "app/static/index.html").read_text(encoding="utf-8")
    javascript = (ROOT / "app/static/app.js").read_text(encoding="utf-8")
    assert 'id="observation-actions"' in html
    assert "investigation.observation_form" in javascript
    assert "/investigation/structured-observations" in javascript
    assert "currentJob.investigation = await response.json()" in javascript
