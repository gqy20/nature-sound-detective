"""Run the production analyzers against a resumable evaluation manifest."""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.audio import prepare_audio
from app.birdnet_service import BirdNetAnalyzer
from app.evaluation import score_case, summarize
from app.pipeline import AnalysisPipeline
from app.yamnet_service import YamNetAnalyzer


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def birdnet_result(raw: dict[str, Any]) -> dict[str, Any]:
    birds = [item for item in raw.get("detections", []) if float(item.get("confidence", 0)) >= 0.25]
    return {
        "primary_sound_type": "鸟类鸣叫" if birds else "无法判断",
        "bird_species": birds,
        "models": {"bird_species": raw.get("model")},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path("data/metadata/mvp_evaluation_manifest.csv"))
    parser.add_argument("--mode", choices=("birdnet", "yamnet", "full"), default="birdnet")
    parser.add_argument("--task", choices=("auto", "sound", "species", "all"), default="auto")
    parser.add_argument("--limit", type=int, default=0, help="0 means all selected cases")
    parser.add_argument("--include-weak", action="store_true")
    parser.add_argument("--case-id", action="append", default=[])
    parser.add_argument("--refresh", action="store_true", help="ignore reusable inference cache")
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/evaluation"))
    args = parser.parse_args()

    rows = [row for row in read_csv(args.manifest) if row.get("include", "yes") == "yes"]
    if not args.include_weak:
        rows = [row for row in rows if row.get("label_status") == "verified"]
    if args.case_id:
        wanted = set(args.case_id)
        rows = [row for row in rows if row.get("case_id") in wanted]
    task = ("species" if args.mode == "birdnet" else "sound") if args.task == "auto" else args.task
    if task == "species":
        rows = [row for row in rows if row.get("expected_species", "").strip()]
    elif task == "sound":
        rows = [row for row in rows if row.get("expected_sound_types", "").strip()]
    if args.limit > 0:
        rows = rows[: args.limit]
    if not rows:
        raise SystemExit("没有可评测样本；人工确认标签后运行，或显式添加 --include-weak 做探索性评测。")

    run_dir = args.output_dir / datetime.now().strftime("%Y%m%d-%H%M%S")
    cache_dir = args.output_dir / "cache" / args.mode
    run_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)
    if args.mode == "birdnet":
        analyzer: Any = BirdNetAnalyzer()
    elif args.mode == "yamnet":
        analyzer = YamNetAnalyzer()
    else:
        analyzer = AnalysisPipeline()
    results: list[dict[str, Any]] = []

    with TemporaryDirectory(prefix="nature-eval-") as temp:
        for index, case in enumerate(rows, 1):
            case_id = case["case_id"]
            cache_path = cache_dir / f"{case_id}.json"
            print(f"[{index}/{len(rows)}] {case_id}", flush=True)
            started = time.perf_counter()
            try:
                source = Path(case["local_path"])
                if not source.exists():
                    raise FileNotFoundError(str(source))
                if cache_path.exists() and not args.refresh:
                    result = json.loads(cache_path.read_text(encoding="utf-8"))
                    cached = True
                else:
                    prepared = Path(temp) / f"{case_id}.wav"
                    general = Path(temp) / f"{case_id}-16k.wav"
                    prepare_audio(source, prepared, general)
                    if args.mode == "birdnet":
                        result = birdnet_result(analyzer.analyze(prepared))
                    elif args.mode == "yamnet":
                        result = analyzer.analyze(general, case.get("location", "杭州"))
                    else:
                        result = analyzer.run(
                            prepared,
                            case.get("location", "杭州"),
                            lambda *_: None,
                            general_audio_path=general,
                        )
                    cache_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
                    cached = False
                row = {
                    **case,
                    **score_case(case, result),
                    "mode": args.mode,
                    "cached": cached,
                    "elapsed_seconds": round(time.perf_counter() - started, 3),
                    "result": result,
                }
            except Exception as exc:
                row = {**case, "mode": args.mode, "error": f"{type(exc).__name__}: {exc}"}
            results.append(row)

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "mode": args.mode,
        "manifest": str(args.manifest),
        "includes_weak_labels": args.include_weak,
        **summarize(results),
    }
    (run_dir / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    (run_dir / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output_dir / f"latest-{args.mode}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"run_dir={run_dir.resolve()}")
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
