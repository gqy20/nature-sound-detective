from pathlib import Path

import app.jobs as jobs_module
from app.jobs import JobStore
from app.pipeline import AnalysisPipeline


class _Preloadable:
    def __init__(self, name: str):
        self.name = name
        self.calls = 0

    def preload(self):
        self.calls += 1
        return {"status": "ready", "duration_ms": 1}


class _Qwen:
    def analyze(self, audio_path: Path, location: str):
        return {"model": "fake", "sound_types": ["无法判断"]}


def test_pipeline_preloads_local_models_without_constructing_cloud_client():
    birdnet = _Preloadable("birdnet")
    nonbird = _Preloadable("nonbird")
    pipeline = AnalysisPipeline(birdnet=birdnet, nonbird=nonbird)

    report = pipeline.preload()

    assert report["status"] == "ready"
    assert report["components"]["birdnet"]["status"] == "ready"
    assert birdnet.calls == 1
    assert nonbird.calls == 1
    assert pipeline.qwen is None


class _PreloadedPipeline:
    def preload(self) -> dict[str, object]:
        return {
            "status": "ready",
            "duration_ms": 12,
            "components": {"birdnet": {"status": "ready"}},
        }


def test_job_store_publishes_preload_status(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    store._pipeline = _PreloadedPipeline()  # type: ignore[assignment]
    try:
        status = store.preload()

        assert status["status"] == "ready"
        assert status["duration_ms"] == 12
        assert store.model_status() == status

        status["status"] = "changed"
        assert store.model_status()["status"] == "ready"
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)
