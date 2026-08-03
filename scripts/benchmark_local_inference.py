from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterator


PROCESS_STARTED = time.perf_counter()
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _rss_bytes() -> int:
    try:
        import psutil

        return int(psutil.Process().memory_info().rss)
    except (ImportError, OSError):
        return 0


@contextmanager
def _peak_rss_sampler(interval_seconds: float = 0.05) -> Iterator[Callable[[], int]]:
    peak = _rss_bytes()
    stopped = threading.Event()

    def sample() -> None:
        nonlocal peak
        while not stopped.wait(interval_seconds):
            peak = max(peak, _rss_bytes())

    thread = threading.Thread(target=sample, name="benchmark-memory", daemon=True)
    thread.start()
    try:
        yield lambda: max(peak, _rss_bytes())
    finally:
        stopped.set()
        thread.join(timeout=1)


def _measure(operation: Callable[[], Any]) -> tuple[Any, dict[str, int]]:
    rss_before = _rss_bytes()
    started = time.perf_counter()
    with _peak_rss_sampler() as peak_rss:
        value = operation()
    return value, {
        "duration_ms": round((time.perf_counter() - started) * 1000),
        "rss_before_bytes": rss_before,
        "rss_after_bytes": _rss_bytes(),
        "peak_rss_bytes": peak_rss(),
    }


def _prepare_clip(source: Path, destination: Path, seconds: float) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg is required to build benchmark clips")
    completed = subprocess.run(
        [
            ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-t",
            str(seconds),
            "-ac",
            "1",
            "-ar",
            "48000",
            "-c:a",
            "pcm_s16le",
            str(destination),
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if completed.returncode != 0 or not destination.is_file():
        raise RuntimeError(completed.stderr.strip()[-500:] or "failed to prepare clip")


def _median(values: list[int]) -> int:
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return round((ordered[middle - 1] + ordered[middle]) / 2)


def _summarize(runs: list[dict[str, int]]) -> dict[str, Any]:
    return {
        "runs": runs,
        "median_duration_ms": _median([item["duration_ms"] for item in runs]),
        "max_peak_rss_bytes": max(item["peak_rss_bytes"] for item in runs),
    }


def benchmark(audio_path: Path, durations: list[float], iterations: int) -> dict[str, Any]:
    import_started = time.perf_counter()
    from app.audio import duration_seconds
    from app.birdnet_service import BirdNetAnalyzer
    from app.nonbird_service import NonBirdAnalyzer

    import_ms = round((time.perf_counter() - import_started) * 1000)
    birdnet = BirdNetAnalyzer()
    nonbird = NonBirdAnalyzer()
    preload_report, preload_metrics = _measure(
        lambda: {"birdnet": birdnet.preload(), "nonbird": nonbird.preload()}
    )
    models_ready_ms = round((time.perf_counter() - PROCESS_STARTED) * 1000)

    results: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="xykw-benchmark-") as temporary:
        temporary_dir = Path(temporary)
        for requested_seconds in durations:
            clip = temporary_dir / f"clip-{requested_seconds:g}s.wav"
            _prepare_clip(audio_path, clip, requested_seconds)
            actual_seconds = duration_seconds(clip)
            bird_runs: list[dict[str, int]] = []
            nonbird_runs: list[dict[str, int]] = []
            parallel_runs: list[dict[str, int]] = []
            for _ in range(iterations):
                _, metrics = _measure(lambda: birdnet.analyze(clip))
                bird_runs.append(metrics)
                _, metrics = _measure(lambda: nonbird.analyze(clip))
                nonbird_runs.append(metrics)

                def run_parallel() -> None:
                    with ThreadPoolExecutor(max_workers=2) as executor:
                        futures = [
                            executor.submit(birdnet.analyze, clip),
                            executor.submit(nonbird.analyze, clip),
                        ]
                        for future in futures:
                            future.result()

                _, metrics = _measure(run_parallel)
                parallel_runs.append(metrics)
            results.append(
                {
                    "requested_seconds": requested_seconds,
                    "actual_seconds": actual_seconds,
                    "birdnet": _summarize(bird_runs),
                    "nonbird": _summarize(nonbird_runs),
                    "parallel": _summarize(parallel_runs),
                }
            )

    return {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_audio": str(audio_path.resolve()),
        "environment": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
        },
        "cold_start": {
            "service_import_ms": import_ms,
            "process_to_models_ready_ms": models_ready_ms,
            "preload": preload_metrics,
            "components": preload_report,
        },
        "warm_inference": results,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark cold preload and warm local bioacoustic inference."
    )
    parser.add_argument("audio", type=Path)
    parser.add_argument("--durations", type=float, nargs="+", default=[3, 10, 20])
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "artifacts" / "benchmarks" / "local_inference.json",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.audio.is_file():
        raise SystemExit(f"audio does not exist: {args.audio}")
    if args.iterations < 1 or any(value <= 0 for value in args.durations):
        raise SystemExit("durations and iterations must be positive")
    report = benchmark(args.audio, args.durations, args.iterations)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
