import numpy as np
import pytest

from app.birdnet_service import BirdNetAnalyzer, BirdNetWindows, _window_waveform
from app.pipeline import AnalysisPipeline
from app.species_catalog import load_hangzhou_birdnet_catalog


def test_window_waveform_pads_only_the_last_window():
    waveform = np.ones(144_001, dtype=np.float32)

    windows, starts, ends = _window_waveform(waveform)

    assert windows.shape == (2, 144_000)
    assert starts.tolist() == [0.0, 3.0]
    assert ends.tolist() == pytest.approx([3.0, 3.0 + 1 / 48_000])
    assert windows[1, 0] == 1
    assert np.count_nonzero(windows[1]) == 1


def test_bird_summary_reads_probabilities_by_catalog_output_index():
    species = load_hangzhou_birdnet_catalog()[0]
    scores = np.zeros((2, 6522), dtype=np.float32)
    scores[1, species.output_index] = 0.8
    windows = BirdNetWindows(
        scores=scores,
        embeddings=np.zeros((2, 1024), dtype=np.float32),
        starts=np.asarray([0, 3], dtype=np.float32),
        ends=np.asarray([3, 6], dtype=np.float32),
    )

    result = BirdNetAnalyzer().summarize(windows)

    assert result["detections"][0]["name_zh"] == species.name_zh
    assert result["detections"][0]["confidence"] == 0.8
    assert result["detections"][0]["start_seconds"] == 3


def test_pipeline_reuses_one_birdnet_forward_for_both_heads(tmp_path):
    marker = object()

    class Bird:
        calls = 0

        def infer_windows(self, _path, progress_callback=None):
            self.calls += 1
            if progress_callback is not None:
                progress_callback(marker, 1, 1)
            return marker

        def summarize(self, windows):
            assert windows is marker
            return {"model": "bird", "scope": "test", "detections": []}

    class NonBird:
        def analyze_windows(self, windows):
            assert windows is marker
            return {"model": "nonbird", "detections": [], "available": True}

    class General:
        def analyze(self, _path, _location):
            return {
                "model": "yamnet",
                "sound_types": ["无法判断"],
                "primary_sound_type": "无法判断",
            }

    bird = Bird()
    pipeline = AnalysisPipeline(general=General(), birdnet=bird, nonbird=NonBird())

    updates = []
    pipeline.run(tmp_path / "unused.wav", "杭州", lambda *args: updates.append(args))

    assert bird.calls == 1
    partial_updates = [item for item in updates if len(item) == 3 and item[2]]
    assert partial_updates[0][2]["partial_result"]["processed_windows"] == 1
