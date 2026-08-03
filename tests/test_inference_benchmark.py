from scripts.benchmark_local_inference import _median, _summarize


def test_benchmark_summary_uses_median_and_peak_memory():
    runs = [
        {"duration_ms": 30, "peak_rss_bytes": 100},
        {"duration_ms": 10, "peak_rss_bytes": 300},
        {"duration_ms": 20, "peak_rss_bytes": 200},
    ]

    summary = _summarize(runs)

    assert summary["median_duration_ms"] == 20
    assert summary["max_peak_rss_bytes"] == 300
    assert _median([10, 20]) == 15
