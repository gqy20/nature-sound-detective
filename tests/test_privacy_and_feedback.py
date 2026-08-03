from __future__ import annotations

import os
import time
import json
from pathlib import Path

from fastapi.testclient import TestClient

import app.config as config
import app.main as main
import app.jobs as jobs_module


def test_cleanup_removes_only_expired_runtime_files(tmp_path, monkeypatch):
    uploads = tmp_path / "uploads"
    jobs = tmp_path / "jobs"
    generated = tmp_path / "generated"
    uploads.mkdir()
    jobs.mkdir()
    generated.mkdir()
    old_audio = uploads / "old.wav"
    recent_audio = uploads / "recent.wav"
    old_job = jobs / "old.json"
    for path in (old_audio, recent_audio, old_job):
        path.write_bytes(b"test")
    old_timestamp = time.time() - 26 * 60 * 60
    os.utime(old_audio, (old_timestamp, old_timestamp))
    os.utime(old_job, (old_timestamp, old_timestamp))
    monkeypatch.setattr(config, "UPLOAD_DIR", uploads)
    monkeypatch.setattr(config, "JOB_DIR", jobs)
    monkeypatch.setattr(config, "GENERATED_DIR", generated)

    removed = config.cleanup_expired_runtime()

    assert removed == 2
    assert not old_audio.exists()
    assert not old_job.exists()
    assert recent_audio.exists()


def test_feedback_endpoint_saves_minimal_correction(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "FEEDBACK_DIR", tmp_path)
    client = TestClient(main.app)

    response = client.post(
        "/api/feedback",
        json={"job_id": "job-123", "is_correct": False, "corrected_type": "蛙类鸣叫"},
    )

    assert response.status_code == 201
    saved = list(tmp_path.glob("*.json"))
    assert len(saved) == 1
    assert "蛙类鸣叫" in saved[0].read_text(encoding="utf-8")


def test_feedback_retains_audio_only_with_consent(tmp_path):
    from app.feedback import save_feedback_record

    source = tmp_path / "source.wav"
    source.write_bytes(b"audio")
    job = {
        "audio_path": str(source),
        "location": "杭州植物园",
        "result": {
            "models": {"nonbird_species": "hangzhou-nonbird 0.2.0"},
            "detections": [{"category_id": "frog", "confidence": 0.8}],
        },
    }
    result = save_feedback_record(
        {
            "job_id": "job-1",
            "decision": "wrong",
            "corrected_taxon_id": "other_frog",
            "consent_to_retain_audio": True,
        },
        job=job,
        feedback_dir=tmp_path / "feedback",
    )
    payload = json.loads(
        (tmp_path / "feedback" / f"{result['id']}.json").read_text(encoding="utf-8")
    )
    assert result["audio_retained"] is True
    assert Path(payload["retained_audio_path"]).read_bytes() == b"audio"
    assert payload["review_status"] == "user_reported"


def test_job_store_restores_completed_jobs_after_restart(tmp_path, monkeypatch):
    audio = tmp_path / "kept.wav"
    audio.write_bytes(b"wav")
    payload = {
        "id": "restored-job",
        "status": "completed",
        "stage_message": "完成",
        "location": "杭州",
        "audio_url": "/api/jobs/restored-job/audio",
        "audio_path": str(audio),
        "result": {"sound_types": ["鸟类鸣叫"]},
        "error": None,
    }
    (tmp_path / "restored-job.json").write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
    )
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)

    store = jobs_module.JobStore()
    try:
        assert store.get("restored-job")["status"] == "completed"
        assert store.audio_path("restored-job") == audio
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)
