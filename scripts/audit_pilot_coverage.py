from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import httpx


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.community.catalog import PILOT_PARKS


MEDIUM_POSTS = 6
MEDIUM_OBSERVERS = 3


def summarize_snapshot(snapshot: dict[str, Any], park_name: str) -> dict[str, Any]:
    posts = int(snapshot.get("valid_post_count") or 0)
    observers = int(snapshot.get("independent_observer_count") or 0)
    zones = snapshot.get("zone_summaries") or []
    empty_zones = [
        item.get("zone_name") or item.get("zone_id")
        for item in zones
        if int(item.get("valid_post_count") or 0) == 0
    ]
    missing_posts = max(0, MEDIUM_POSTS - posts)
    missing_observers = max(0, MEDIUM_OBSERVERS - observers)
    ready = (
        snapshot.get("data_sufficiency") in {"medium", "high"}
        and missing_posts == 0
        and missing_observers == 0
    )
    actions = []
    if missing_posts:
        actions.append(f"补充{missing_posts}条有效声音")
    if missing_observers:
        actions.append(f"增加{missing_observers}位独立观察者")
    if empty_zones:
        actions.append(f"优先覆盖空白分区：{'、'.join(empty_zones)}")
    return {
        "park_id": snapshot.get("park_id"),
        "park_name": park_name,
        "ready_for_medium": ready,
        "data_sufficiency": snapshot.get("data_sufficiency", "low"),
        "valid_posts": posts,
        "independent_observers": observers,
        "observation_days": int(snapshot.get("observation_day_count") or 0),
        "missing_posts": missing_posts,
        "missing_observers": missing_observers,
        "empty_zones": empty_zones,
        "next_actions": actions or ["保持跨时段连续观察"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="审计三个试点公园的真实声景数据覆盖")
    parser.add_argument(
        "--base-url",
        default="https://xykw-api.vercel.app",
        help="社区API根地址",
    )
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument(
        "--require-medium",
        action="store_true",
        help="任一公园未达到medium时返回退出码3",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not 1 <= args.days <= 90:
        raise SystemExit("--days 必须在1至90之间")
    reports = []
    with httpx.Client(base_url=args.base_url.rstrip("/"), timeout=30) as client:
        for park in PILOT_PARKS:
            response = client.get(
                f"/api/community/parks/{park['id']}/ecology-snapshot",
                params={"days": args.days},
            )
            response.raise_for_status()
            reports.append(summarize_snapshot(response.json(), park["name"]))
    payload = {
        "period_days": args.days,
        "all_ready_for_medium": all(item["ready_for_medium"] for item in reports),
        "parks": reports,
    }
    if args.as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        for item in reports:
            marker = "READY" if item["ready_for_medium"] else "GAP"
            print(
                f"[{marker}] {item['park_name']}：{item['valid_posts']}条 / "
                f"{item['independent_observers']}人 / {item['observation_days']}天"
            )
            print("  下一步：" + "；".join(item["next_actions"]))
    if args.require_medium and not payload["all_ready_for_medium"]:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
