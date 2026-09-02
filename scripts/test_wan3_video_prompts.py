from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.generated_prompts import PROMPT_CATALOG_DIGEST, prompt_version, render_prompt


MODEL = "wan3.0-video"
RESOLUTION = "480P"
RATIO = "9:16"
DURATION_SECONDS = 5
MAX_VIDEOS = 5


@dataclass(frozen=True)
class PromptCase:
    slug: str
    purpose: str
    prompt: str
    seed: int | None = None
    reference_image_url: str = ""
    reference_attribution: str = ""


EXPERIMENT_CASES = (
    PromptCase(
        slug="01-current-prompt",
        purpose="当前移动端通用提示词基线",
        prompt=render_prompt("wan3_experiments.current_mobile_baseline"),
    ),
    PromptCase(
        slug="02-structured-sparrow",
        purpose="结构化完整鸟类提示词",
        prompt=render_prompt("wan3_experiments.structured_sparrow"),
    ),
    PromptCase(
        slug="03-concise-sparrow",
        purpose="简洁的主体、动作、镜头提示词",
        prompt=render_prompt("wan3_experiments.concise_sparrow"),
    ),
    PromptCase(
        slug="04-structured-frog",
        purpose="结构化蛙类提示词",
        prompt=render_prompt("wan3_experiments.structured_frog"),
    ),
    PromptCase(
        slug="05-uncertain-environment",
        purpose="识别不确定时只生成环境线索",
        prompt=render_prompt("wan3_experiments.uncertain_environment"),
    ),
)

PRODUCTION_CURRENT_CASES = (
    PromptCase(
        slug="01-production-bird",
        purpose="当前移动端鸟类展示效果（杭州树麻雀）",
        prompt=render_prompt(
            "creation.mobile_video_bird",
            location="杭州",
            subject="树麻雀",
        ),
    ),
    PromptCase(
        slug="02-production-frog",
        purpose="当前移动端蛙类展示效果（杭州黑斑侧褶蛙）",
        prompt=render_prompt(
            "creation.mobile_video_frog",
            location="杭州",
            subject="黑斑侧褶蛙",
        ),
    ),
    PromptCase(
        slug="03-production-environment",
        purpose="当前移动端不确定识别的纯环境展示效果",
        prompt=render_prompt(
            "creation.mobile_video_environment",
            location="杭州",
        ),
    ),
)

SHOWCASE_PILOT_CASES = (
    PromptCase(
        slug="01-bird-current",
        purpose="鸟类当前正式提示词基线",
        prompt=render_prompt(
            "creation.mobile_video_bird",
            location="杭州",
            subject="树麻雀",
        ),
        seed=2026090201,
    ),
    PromptCase(
        slug="02-bird-showcase-dynamic",
        purpose="鸟类展示级时间线与动态提示词",
        prompt=render_prompt("wan3_experiments.showcase_bird_dynamic"),
        seed=2026090201,
    ),
    PromptCase(
        slug="03-environment-current",
        purpose="无动物环境当前正式提示词基线",
        prompt=render_prompt(
            "creation.mobile_video_environment",
            location="杭州",
        ),
        seed=2026090202,
    ),
    PromptCase(
        slug="04-environment-showcase-dynamic",
        purpose="无动物环境展示级时间线与动态提示词",
        prompt=render_prompt("wan3_experiments.showcase_environment_dynamic"),
        seed=2026090202,
    ),
)

SHOWCASE_FIX_CASES = (
    PromptCase(
        slug="01-environment-showcase-fixed",
        purpose="修正城市天际线误生成的纯自然湿地动态片",
        prompt=render_prompt("wan3_experiments.showcase_environment_dynamic_v2"),
        seed=2026090202,
    ),
    PromptCase(
        slug="02-frog-showcase-text-only",
        purpose="蛙类展示级动态提示词纯文字基线",
        prompt=render_prompt("wan3_experiments.showcase_frog_dynamic"),
        seed=2026090203,
    ),
    PromptCase(
        slug="03-frog-showcase-reference",
        purpose="蛙类展示级动态提示词加可信物种参考图",
        prompt=render_prompt("wan3_experiments.showcase_frog_dynamic"),
        seed=2026090203,
        reference_image_url=(
            "https://inaturalist-open-data.s3.amazonaws.com/"
            "photos/47127806/original.jpg"
        ),
        reference_attribution=(
            "Pelophylax nigromaculatus; Kim, Hyun-tae; "
            "iNaturalist photo 47127806; CC BY 4.0"
        ),
    ),
)

SHOWCASE_FROG_FIX_CASES = (
    PromptCase(
        slug="01-frog-reference-low-motion",
        purpose="参考图蛙类低幅度爬入浅水修正版",
        prompt=render_prompt("wan3_experiments.showcase_frog_dynamic_v2"),
        seed=2026090203,
        reference_image_url=(
            "https://inaturalist-open-data.s3.amazonaws.com/"
            "photos/47127806/original.jpg"
        ),
        reference_attribution=(
            "Pelophylax nigromaculatus; Kim, Hyun-tae; "
            "iNaturalist photo 47127806; CC BY 4.0"
        ),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="用 Wan 3.0 生成最多5个480P、5秒提示词测试视频。",
    )
    parser.add_argument(
        "--suite",
        choices=(
            "experiments",
            "production-current",
            "showcase-pilot",
            "showcase-fix",
            "showcase-frog-fix",
        ),
        default="experiments",
        help="提示词套件：历史实验或当前移动端正式提示词。",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=None,
        help="运行套件中的前几个用例；默认运行所选套件的全部用例。",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="视频、任务状态和实验清单的输出目录。",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=10.0,
        help="任务轮询间隔秒数，默认10。",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=600.0,
        help="等待全部任务的最长秒数，默认600。",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="实际提交付费任务；不传时只输出计划。",
    )
    return parser.parse_args()


def api_base() -> str:
    configured = os.getenv("DASHSCOPE_AIGC_BASE_URL", "").strip().rstrip("/")
    if configured:
        return configured
    compatible = os.getenv(
        "DASHSCOPE_BASE_URL",
        "https://dashscope.aliyuncs.com/compatible-mode/v1",
    ).strip()
    return compatible.replace("/compatible-mode/v1", "/api/v1").rstrip("/")


def prompt_id(prompt: str) -> str:
    return hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:12]


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def error_message(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        return response.text[:800]
    return json.dumps(payload, ensure_ascii=False)[:800]


def submit_case(
    client: httpx.Client,
    base: str,
    headers: dict[str, str],
    case: PromptCase,
    negative_prompt: str,
) -> str:
    input_payload: dict[str, Any] = {
        "prompt": case.prompt,
        "negative_prompt": negative_prompt,
    }
    if case.reference_image_url:
        input_payload["media"] = [
            {"type": "reference_image", "url": case.reference_image_url}
        ]
    response = client.post(
        f"{base}/services/aigc/video-generation/video-synthesis",
        headers={**headers, "X-DashScope-Async": "enable"},
        json={
            "model": MODEL,
            "input": input_payload,
            "parameters": {
                "resolution": RESOLUTION,
                "ratio": RATIO,
                "duration": DURATION_SECONDS,
                "audio": False,
                "prompt_extend": True,
                "watermark": True,
                **({"seed": case.seed} if case.seed is not None else {}),
            },
        },
    )
    if response.is_error:
        raise RuntimeError(f"创建失败：{error_message(response)}")
    payload = response.json()
    task_id = str(payload.get("output", {}).get("task_id") or "")
    if not task_id:
        raise RuntimeError(f"没有返回task_id：{error_message(response)}")
    return task_id


def download_video(client: httpx.Client, url: str, destination: Path) -> None:
    temporary = destination.with_suffix(destination.suffix + ".part")
    try:
        with client.stream("GET", url) as response:
            response.raise_for_status()
            with temporary.open("wb") as handle:
                for chunk in response.iter_bytes():
                    handle.write(chunk)
        if temporary.stat().st_size <= 0:
            raise RuntimeError("下载结果为空")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    args = parse_args()
    if args.suite == "production-current":
        available_cases = PRODUCTION_CURRENT_CASES
        negative_prompt = render_prompt("creation.mobile_video_negative")
        prompt_namespace = "creation"
    elif args.suite == "showcase-pilot":
        available_cases = SHOWCASE_PILOT_CASES
        negative_prompt = render_prompt("creation.mobile_video_negative")
        prompt_namespace = "wan3_experiments"
    elif args.suite == "showcase-fix":
        available_cases = SHOWCASE_FIX_CASES
        negative_prompt = render_prompt("creation.mobile_video_negative")
        prompt_namespace = "wan3_experiments"
    elif args.suite == "showcase-frog-fix":
        available_cases = SHOWCASE_FROG_FIX_CASES
        negative_prompt = render_prompt("creation.mobile_video_negative")
        prompt_namespace = "wan3_experiments"
    else:
        available_cases = EXPERIMENT_CASES
        negative_prompt = render_prompt("wan3_experiments.negative")
        prompt_namespace = "wan3_experiments"
    count = len(available_cases) if args.count is None else args.count
    if not 1 <= count <= len(available_cases):
        raise SystemExit(f"--count 必须在1到{len(available_cases)}之间")
    if args.poll_interval < 2:
        raise SystemExit("--poll-interval 不能小于2秒")
    if args.timeout <= 0:
        raise SystemExit("--timeout 必须大于0")

    load_dotenv(ROOT / ".env")
    cases = list(available_cases[:count])
    default_run_name = (
        {
            "production-current": "003-wan3-creation-v2",
            "showcase-pilot": "004-wan3-showcase-pilot-v1",
            "showcase-fix": "005-wan3-showcase-fix-v2",
            "showcase-frog-fix": "006-wan3-showcase-frog-fix-v3",
        }.get(args.suite, "002-wan3-480p-prompt-test")
    )
    output_dir = (
        args.output_dir
        or ROOT
        / "mobile"
        / "qa"
        / "runs"
        / datetime.now().strftime("%Y-%m-%d")
        / default_run_name
    ).resolve()
    plan = {
        "model": MODEL,
        "resolution": RESOLUTION,
        "ratio": RATIO,
        "duration_seconds": DURATION_SECONDS,
        "suite": args.suite,
        "prompt_namespace": prompt_namespace,
        "prompt_version": prompt_version(prompt_namespace),
        "prompt_catalog_digest": PROMPT_CATALOG_DIGEST,
        "count": len(cases),
        "output_dir": str(output_dir),
        "cases": [
            {
                "slug": case.slug,
                "purpose": case.purpose,
                "prompt_id": prompt_id(case.prompt),
                "seed": case.seed,
                "reference_image_url": case.reference_image_url,
                "reference_attribution": case.reference_attribution,
                "prompt": case.prompt,
            }
            for case in cases
        ],
    }
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    if not args.execute:
        print("\n计划模式：未提交视频。确认后加 --execute。")
        return 0

    api_key = os.getenv("DASHSCOPE_API_KEY", "").strip()
    if not api_key:
        raise SystemExit(".env 中缺少 DASHSCOPE_API_KEY")

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "manifest.json"
    manifest: dict[str, Any] = {
        **plan,
        "started_at": datetime.now().astimezone().isoformat(),
        "status": "submitting",
        "results": [],
    }
    write_manifest(manifest_path, manifest)

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    transport = httpx.HTTPTransport(retries=3)
    timeout = httpx.Timeout(90, connect=30)
    with httpx.Client(timeout=timeout, transport=transport) as client:
        for case in cases:
            result = {
                "slug": case.slug,
                "purpose": case.purpose,
                "prompt_id": prompt_id(case.prompt),
                "seed": case.seed,
                "reference_image_url": case.reference_image_url,
                "reference_attribution": case.reference_attribution,
                "status": "submitting",
                "task_id": "",
                "file": f"{case.slug}.mp4",
            }
            manifest["results"].append(result)
            write_manifest(manifest_path, manifest)
            try:
                result["task_id"] = submit_case(
                    client,
                    api_base(),
                    headers,
                    case,
                    negative_prompt,
                )
                result["status"] = "submitted"
                print(f"[{case.slug}] submitted task={result['task_id']}")
            except Exception as error:  # noqa: BLE001 - keep later cases runnable
                result["status"] = "submit_failed"
                result["error"] = str(error)
                print(f"[{case.slug}] submit failed: {error}", file=sys.stderr)
            write_manifest(manifest_path, manifest)

        manifest["status"] = "polling"
        write_manifest(manifest_path, manifest)
        deadline = time.monotonic() + args.timeout
        pending = {
            result["task_id"]: result
            for result in manifest["results"]
            if result["status"] == "submitted"
        }
        while pending and time.monotonic() < deadline:
            for task_id, result in list(pending.items()):
                response = client.get(
                    f"{api_base()}/tasks/{task_id}",
                    headers={"Authorization": f"Bearer {api_key}"},
                )
                if response.is_error:
                    print(
                        f"[{result['slug']}] poll warning: {error_message(response)}",
                        file=sys.stderr,
                    )
                    continue
                output = response.json().get("output", {})
                status = str(output.get("task_status") or "UNKNOWN")
                if status == "SUCCEEDED":
                    video_url = str(output.get("video_url") or "")
                    if not video_url:
                        result["status"] = "failed"
                        result["error"] = "任务成功但没有返回video_url"
                    else:
                        destination = output_dir / result["file"]
                        download_video(client, video_url, destination)
                        result["status"] = "succeeded"
                        result["bytes"] = destination.stat().st_size
                        print(f"[{result['slug']}] saved {destination}")
                    pending.pop(task_id)
                elif status in {"FAILED", "CANCELED", "UNKNOWN"}:
                    result["status"] = "failed"
                    result["error"] = str(output.get("message") or status)
                    pending.pop(task_id)
                    print(
                        f"[{result['slug']}] failed: {result['error']}",
                        file=sys.stderr,
                    )
                else:
                    result["status"] = status.lower()
            write_manifest(manifest_path, manifest)
            if pending:
                time.sleep(args.poll_interval)

    for result in pending.values():
        result["status"] = "timeout"
        result["error"] = f"等待超过{args.timeout:g}秒，可按task_id继续查询"
    succeeded = sum(result["status"] == "succeeded" for result in manifest["results"])
    manifest["finished_at"] = datetime.now().astimezone().isoformat()
    manifest["status"] = "completed" if succeeded == len(cases) else "partial"
    manifest["succeeded"] = succeeded
    write_manifest(manifest_path, manifest)
    print(f"完成：{succeeded}/{len(cases)}，清单：{manifest_path}")
    return 0 if succeeded == len(cases) else 1


if __name__ == "__main__":
    raise SystemExit(main())
