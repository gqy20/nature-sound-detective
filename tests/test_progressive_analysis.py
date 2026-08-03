import app.jobs as jobs_module
from app.jobs import JobStore


class _ProgressivePipeline:
    def run(self, _audio_path, _location, progress, **_kwargs):
        partial = {
            "processed_windows": 1,
            "total_windows": 2,
            "bird_species": [{"name_zh": "珠颈斑鸠", "confidence": 0.8}],
            "nonbird_species": [],
        }
        progress(
            "analyzing",
            "已经听完第 1/2 段",
            {
                "partial_result": partial,
                "analysis_progress": {"processed_windows": 1, "total_windows": 2},
            },
        )
        return {"primary_sound_type": "鸟类鸣叫"}


def test_job_store_publishes_partial_results_before_completion(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    store._pipeline = _ProgressivePipeline()  # type: ignore[assignment]
    job = {
        "id": "progressive-job",
        "trace_id": "test",
        "audio_path": str(tmp_path / "audio.wav"),
        "general_audio_path": str(tmp_path / "audio.wav"),
        "location": "杭州",
        "status": "queued",
        "stage_message": "准备中",
        "result": None,
        "creation": {"status": "idle", "stage_message": ""},
    }
    store._jobs[job["id"]] = job
    try:
        store._run_with_trace(job["id"], job)

        published = store.get(job["id"])
        assert published["status"] == "completed"
        assert published["partial_result"]["processed_windows"] == 1
        assert published["analysis_progress"] == {
            "processed_windows": 1,
            "total_windows": 2,
        }
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)
