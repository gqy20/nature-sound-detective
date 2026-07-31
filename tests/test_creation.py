from app.creation_service import build_creation_plan
import json

import app.jobs as jobs_module
from app.jobs import JobStore


def test_creation_plan_stays_within_identified_sound_type():
    result = {
        "primary_sound_type": "风和树叶",
        "card": {
            "title": "风经过树林",
            "explanation": "风吹过不同形状的叶片，会形成轻重不同的沙沙声。",
            "question": "风声是一阵一阵的吗？",
        },
    }
    plan = build_creation_plan(result, "杭州植物园")
    assert "风和树叶" in plan["music_prompt"]
    assert "杭州" in plan["video_prompt"]
    assert "无字幕" in plan["video_prompt"]
    assert "具体动物近景" in plan["video_prompt"]
    assert "杭州植物园" in plan["narration"]
    assert "风和树叶" in plan["narration"]


def test_public_job_never_exposes_server_media_paths():
    job = {
        "id": "job",
        "audio_path": "secret.wav",
        "creation": {
            "status": "completed",
            "music_path": "private-music.mp3",
            "narration_path": "private-narration.mp3",
            "video_path": "private-video.mp4",
            "music_url": "/api/music",
            "video_url": "/api/video",
        },
    }
    public = JobStore.public(job)
    assert "audio_path" not in public
    assert "music_path" not in public["creation"]
    assert "narration_path" not in public["creation"]
    assert "video_path" not in public["creation"]
    assert public["creation"]["video_url"] == "/api/video"


def test_restart_turns_interrupted_creation_into_retryable_state(tmp_path, monkeypatch):
    audio = tmp_path / "recording.wav"
    music = tmp_path / "music.mp3"
    audio.write_bytes(b"audio")
    music.write_bytes(b"music")
    payload = {
        "id": "interrupted",
        "status": "completed",
        "audio_path": str(audio),
        "result": {"primary_sound_type": "风和树叶"},
        "creation": {
            "status": "generating_video",
            "music_path": str(music),
            "music_url": "/api/jobs/interrupted/creation/music",
        },
    }
    (tmp_path / "interrupted.json").write_text(json.dumps(payload), encoding="utf-8")
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    try:
        restored = store.get("interrupted")
        assert restored["creation"]["status"] == "partial"
        assert "重新生成" in restored["creation"]["stage_message"]
        assert "music_path" not in restored["creation"]
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)
