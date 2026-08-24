from __future__ import annotations

import argparse
import json
import logging
import os
import platform
import shutil
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Sequence

from dotenv import load_dotenv

from app.audio import duration_seconds, prepare_audio
from app.config import ROOT
from app.investigation import apply_observation, build_investigation, replay_investigation
from app.observability import normalize_trace_id, trace_context
from app.result_fusion import fuse_results
from app.run_artifacts import (
    base_run_manifest,
    create_run_id,
    load_run_package,
    update_investigation,
    write_run_package,
)


DEFAULT_RUN_ROOT = ROOT / "artifacts" / "cli-runs"


def _route_application_logs_to_stderr() -> None:
    """Keep stdout machine-readable when CLI commands use --json."""
    for handler in logging.getLogger("xykw").handlers:
        if hasattr(handler, "setStream"):
            handler.setStream(sys.stderr)


def _emit(payload: Any, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    if isinstance(payload, str):
        print(payload)
        return
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def _doctor(_args: argparse.Namespace) -> int:
    load_dotenv(ROOT / ".env")
    checks = {
        "python_3_11": sys.version_info[:2] == (3, 11),
        "ffmpeg": bool(shutil.which("ffmpeg")),
        "ffprobe": bool(shutil.which("ffprobe")),
        "birdnet_mobile_model": (ROOT / "mobile/assets/models/birdnet.tflite").is_file(),
        "nonbird_mobile_model": (ROOT / "mobile/assets/models/nonbird.tflite").is_file(),
        "yamnet_server_model": (ROOT / "mobile/assets/models/yamnet.tflite").is_file(),
        "minimax_configured": bool(os.getenv("MINIMAX_API_KEY")),
        "wan_live_enabled": os.getenv("WAN_VIDEO_MODE", "mock").strip().lower() == "live",
    }
    required = (
        "python_3_11", "ffmpeg", "ffprobe", "yamnet_server_model",
        "birdnet_mobile_model", "nonbird_mobile_model",
    )
    payload = {
        "ok": all(checks[key] for key in required),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "checks": checks,
        "notes": ["CLI分析全部使用本地声学模型，不触发大模型、音乐或视频费用。"],
    }
    _emit(payload, as_json=_args.json)
    return 0 if payload["ok"] else 1


def _run_analysis(
    source: Path,
    *,
    location: str,
    mode: str,
    trace_id: str,
) -> tuple[dict[str, Any], list[dict[str, Any]], float]:
    progress_events: list[dict[str, Any]] = []
    started = time.perf_counter()

    def progress(status: str, message: str, details: dict[str, Any] | None = None) -> None:
        progress_events.append(
            {
                "status": status,
                "message": message,
                "details": details or {},
                "elapsed_ms": round((time.perf_counter() - started) * 1000),
            }
        )

    with tempfile.TemporaryDirectory(prefix="xykw-cli-") as temporary:
        temp = Path(temporary)
        bioacoustic = temp / "bioacoustic.wav"
        general = temp / "general.wav"
        prepare_audio(source, bioacoustic, general)
        with trace_context(trace_id):
            if mode == "full":
                from app.pipeline import AnalysisPipeline

                _route_application_logs_to_stderr()

                result = AnalysisPipeline().run(
                    bioacoustic,
                    location,
                    progress,
                    general_audio_path=general,
                )
            elif mode == "acoustic":
                from app.birdnet_service import BirdNetAnalyzer
                from app.nonbird_service import NonBirdAnalyzer

                _route_application_logs_to_stderr()

                progress("analyzing", "正在运行本地专业声学模型", None)
                birdnet_analyzer = BirdNetAnalyzer()
                windows = birdnet_analyzer.infer_windows(bioacoustic)
                birdnet = birdnet_analyzer.summarize(windows)
                try:
                    nonbird = NonBirdAnalyzer().analyze_windows(windows)
                except Exception as exc:
                    nonbird = {
                        "model": "hangzhou-nonbird-unavailable",
                        "scope": "杭州本地蛙类与鸣虫",
                        "detections": [],
                        "available": False,
                        "warning": str(exc),
                    }
                result = fuse_results(
                    {
                        "sound_types": ["无法判断"],
                        "primary_sound_type": "无法判断",
                        "confidence_level": "low",
                        "model": "cli-specialist-only",
                        "evidence": [],
                        "uncertainty": "未运行YAMNet通用声景模型",
                    },
                    birdnet,
                    nonbird,
                )
                progress("composing", "本地声学证据已经整理完成", None)
            else:
                from app.yamnet_service import YamNetAnalyzer

                _route_application_logs_to_stderr()

                progress("analyzing", "正在运行YAMNet通用声景分析", None)
                yamnet = YamNetAnalyzer().analyze(general, location)
                result = fuse_results(
                    yamnet,
                    {"model": None, "scope": "未运行", "detections": []},
                    {"model": None, "scope": "未运行", "detections": [], "available": False},
                )
                progress("composing", "YAMNet声景结果已经整理完成", None)
        return result, progress_events, duration_seconds(bioacoustic)


def _analyze(args: argparse.Namespace) -> int:
    load_dotenv(ROOT / ".env")
    source = args.audio.resolve()
    if not source.is_file():
        raise FileNotFoundError(f"录音不存在：{source}")
    run_id = create_run_id(source.stem)
    trace_id = normalize_trace_id(f"cli-{run_id}")
    result, progress, duration = _run_analysis(
        source,
        location=args.location,
        mode=args.mode,
        trace_id=trace_id,
    )
    investigation = build_investigation(
        result,
        args.location,
        investigation_id=f"cli-{run_id}",
    )
    manifest = base_run_manifest(run_id, location=args.location, mode=args.mode, source=source)
    manifest.update(
        {
            "trace_id": trace_id,
            "duration_seconds": duration,
            "status": "completed",
        }
    )
    run_dir = write_run_package(
        args.output_dir.resolve(),
        run=manifest,
        result=result,
        investigation=investigation,
        progress=progress,
    )
    payload = {
        "run_dir": str(run_dir),
        "run_id": run_id,
        "trace_id": trace_id,
        "primary_sound_type": result.get("primary_sound_type"),
        "confidence_level": result.get("confidence_level"),
        "candidate_count": len(investigation["evidence"]["candidates"]),
        "investigation_status": investigation["status"],
        "question": investigation["question"],
    }
    _emit(payload, as_json=args.json)
    return 0


def _inspect(args: argparse.Namespace) -> int:
    package = load_run_package(args.run_dir.resolve())
    investigation = package["investigation"]
    if args.stage == "all":
        payload = package
    else:
        payload = package[args.stage]
    _emit(payload, as_json=args.json)
    if not args.json and args.stage == "all":
        print(f"\n调查状态：{investigation.get('status')} · 轮次 {investigation.get('round')}")
    return 0


def _investigate(args: argparse.Namespace) -> int:
    run_dir = args.run_dir.resolve()
    package = load_run_package(run_dir)
    investigation = package["investigation"]
    question_id = args.question_id or str(investigation.get("question", {}).get("id") or "")
    updated = apply_observation(
        investigation,
        question_id=question_id,
        choice=args.choice,
        note=args.note,
        source="cli",
    )
    update_investigation(run_dir, updated)
    _emit(
        {
            "run_dir": str(run_dir),
            "investigation_status": updated["status"],
            "round": updated["round"],
            "stop_reason": updated["stop_reason"],
            "observation": updated["observations"][-1],
        },
        as_json=args.json,
    )
    return 0


def _replay(args: argparse.Namespace) -> int:
    run_dir = args.run_dir.resolve()
    package = load_run_package(run_dir)
    replayed = replay_investigation(package)
    output = run_dir / "replayed-investigation.json"
    output.write_text(json.dumps(replayed, ensure_ascii=False, indent=2), encoding="utf-8")
    same_state = {
        key: replayed.get(key) == package["investigation"].get(key)
        for key in ("status", "round", "evidence", "observations", "stop_reason")
    }
    payload = {
        "run_dir": str(run_dir),
        "output": str(output),
        "consistent": all(same_state.values()),
        "checks": same_state,
    }
    _emit(payload, as_json=args.json)
    return 0 if payload["consistent"] else 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nature-sound-cli", description="自然声探员调查链路调试工具")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def json_flag(command: argparse.ArgumentParser) -> None:
        command.add_argument("--json", action="store_true", help="输出机器可读JSON")

    doctor = subparsers.add_parser("doctor", help="检查本机环境、模型和云端配置")
    json_flag(doctor)
    doctor.set_defaults(handler=_doctor)

    analyze = subparsers.add_parser("analyze", help="分析单条录音并生成可回放运行包")
    analyze.add_argument("audio", type=Path)
    analyze.add_argument("--location", default="杭州")
    analyze.add_argument("--mode", choices=("full", "acoustic", "yamnet"), default="full")
    analyze.add_argument("--output-dir", type=Path, default=DEFAULT_RUN_ROOT)
    json_flag(analyze)
    analyze.set_defaults(handler=_analyze)

    inspect = subparsers.add_parser("inspect", help="查看已经保存的调查运行包")
    inspect.add_argument("run_dir", type=Path)
    inspect.add_argument("--stage", choices=("all", "run", "result", "investigation", "progress"), default="all")
    json_flag(inspect)
    inspect.set_defaults(handler=_inspect)

    investigate = subparsers.add_parser("investigate", aliases=["observe"], help="提交一项现场观察")
    investigate.add_argument("run_dir", type=Path)
    investigate.add_argument("--choice", choices=("observed", "not_observed", "unknown"), required=True)
    investigate.add_argument("--note", default="")
    investigate.add_argument("--question-id")
    json_flag(investigate)
    investigate.set_defaults(handler=_investigate)

    replay = subparsers.add_parser("replay", help="离线重建调查状态并检查一致性")
    replay.add_argument("run_dir", type=Path)
    json_flag(replay)
    replay.set_defaults(handler=_replay)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        if getattr(args, "json", False):
            print(json.dumps({"error": type(exc).__name__, "message": str(exc)}, ensure_ascii=False))
        else:
            print(f"错误：{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
