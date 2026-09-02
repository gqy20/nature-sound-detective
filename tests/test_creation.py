from pathlib import Path

import app.creation_service as creation_module
from app.creation_service import build_creation_plan, prepare_video
import json
import pytest

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
    investigation = {
        "status": "completed",
        "observations": [{"choice": "observed"}],
    }
    plan = build_creation_plan(result, "杭州植物园", investigation)
    assert "风和树叶" in plan["music_prompt"]
    assert "杭州" in plan["video_prompt"]
    assert "无字幕" in plan["video_prompt"]
    assert "具体动物近景" in plan["video_prompt"]
    assert "杭州植物园" in plan["narration"]
    assert "风和树叶" in plan["narration"]
    assert plan["investigation_status"] == "completed"
    assert "现场观察" in plan["observation_summary"]
    assert "不是最终鉴定" in plan["narration"]
    assert plan["prompt_version"] == "creation-v3"


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


def test_default_video_mode_uses_local_mock_without_live_api(tmp_path, monkeypatch):
    destination = tmp_path / "mock.mp4"
    monkeypatch.delenv("WAN_VIDEO_MODE", raising=False)
    monkeypatch.setattr(
        creation_module, "create_mock_video",
        lambda path, duration: Path(path).write_bytes(f"mock-{duration}".encode()),
    )
    monkeypatch.setattr(
        creation_module, "generate_wan_video",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("live API must not run")),
    )
    provider, task_id = prepare_video("prompt", destination, 12)
    assert provider == "local-mock-video"
    assert task_id == ""
    assert destination.read_bytes() == b"mock-12"


def test_reuse_video_mode_prefers_configured_asset(tmp_path, monkeypatch):
    source = tmp_path / "sample.mp4"
    destination = tmp_path / "output.mp4"
    source.write_bytes(b"sample")
    monkeypatch.setenv("WAN_VIDEO_MODE", "reuse")
    monkeypatch.setenv("WAN_VIDEO_REUSE_PATH", str(source))
    monkeypatch.setattr(
        creation_module, "reuse_video",
        lambda source_path, target, duration: Path(target).write_bytes(Path(source_path).read_bytes()),
    )
    provider, task_id = prepare_video("prompt", destination, 10)
    assert provider == "reused-demo-video"
    assert task_id == ""
    assert destination.read_bytes() == b"sample"


def test_live_video_mode_defaults_to_wan_2_7(tmp_path, monkeypatch):
    destination = tmp_path / "wan.mp4"
    monkeypatch.setenv("WAN_VIDEO_MODE", "live")
    monkeypatch.delenv("WAN_VIDEO_MODEL", raising=False)
    monkeypatch.setattr(
        creation_module,
        "generate_wan_video",
        lambda *args, **kwargs: "wan-3-task",
    )
    provider, task_id = prepare_video("prompt", destination, 10)
    assert provider == "wan3.0-video"
    assert task_id == "wan-3-task"


def test_retry_preserves_persisted_wan_task_id(tmp_path, monkeypatch):
    audio = tmp_path / "recording.wav"
    music = tmp_path / "music.mp3"
    audio.write_bytes(b"audio")
    music.write_bytes(b"music")
    payload = {
        "id": "resume-video",
        "status": "completed",
        "audio_path": str(audio),
        "location": "杭州",
        "result": {"primary_sound_type": "风和树叶"},
        "creation": {
            "status": "generating_video",
            "music_path": str(music),
            "wan_task_id": "wan-existing-task",
        },
    }
    (tmp_path / "resume-video.json").write_text(json.dumps(payload), encoding="utf-8")
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    try:
        assert store.get("resume-video")["creation"]["status"] == "partial"
        store._creation_executor.shutdown(wait=True)
        class NoopExecutor:
            @staticmethod
            def submit(*_args, **_kwargs):
                return None

            @staticmethod
            def shutdown(*_args, **_kwargs):
                return None

        store._creation_executor = NoopExecutor()
        queued = store.start_creation("resume-video")
        assert queued["creation"]["status"] == "queued"
        assert queued["creation"]["wan_task_id"] == "wan-existing-task"
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)


def test_new_creation_requires_terminal_investigation(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    store._jobs["awaiting"] = {
        "id": "awaiting",
        "status": "completed",
        "audio_path": str(tmp_path / "audio.wav"),
        "location": "杭州",
        "result": {"primary_sound_type": "风和树叶"},
        "investigation": {"status": "awaiting_observation"},
        "creation": {"status": "idle"},
    }
    try:
        with pytest.raises(ValueError, match="现场观察"):
            store.start_creation("awaiting")
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)
