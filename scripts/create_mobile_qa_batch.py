from __future__ import annotations

import argparse
import re
import subprocess
from datetime import date
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNS_ROOT = REPO_ROOT / "mobile" / "qa" / "runs"


def _git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip()


def _next_batch(day_dir: Path) -> int:
    values: list[int] = []
    if day_dir.exists():
        for item in day_dir.iterdir():
            match = re.match(r"^(\d{3})-", item.name)
            if match:
                values.append(int(match.group(1)))
    return max(values, default=0) + 1


def main() -> None:
    parser = argparse.ArgumentParser(description="创建移动端交互验证归档批次")
    parser.add_argument("--slug", required=True, help="英文短标识，例如 map-fullscreen")
    parser.add_argument("--title", required=True, help="批次中文标题")
    parser.add_argument("--date", default=date.today().isoformat(), dest="run_date")
    parser.add_argument("--batch", type=int, help="三位批次编号，默认自动递增")
    args = parser.parse_args()

    slug = re.sub(r"[^a-z0-9-]+", "-", args.slug.lower()).strip("-")
    if not slug:
        raise SystemExit("--slug 必须包含英文、数字或连字符")

    day_dir = RUNS_ROOT / args.run_date
    batch = args.batch or _next_batch(day_dir)
    run_dir = day_dir / f"{batch:03d}-{slug}"
    if run_dir.exists():
        raise SystemExit(f"批次已存在：{run_dir}")

    for name in ("screenshots", "references", "ui-tree", "logs", "artifacts"):
        (run_dir / name).mkdir(parents=True, exist_ok=False)

    branch = _git("branch", "--show-current") or "unknown"
    commit = _git("rev-parse", "--short", "HEAD") or "unknown"
    dirty = bool(_git("status", "--short"))
    manifest = f"""# {args.title}

- Status: `PARTIAL`
- Date: `{args.run_date}`
- Batch: `{batch:03d}`
- Branch: `{branch}`
- Base commit: `{commit}`
- Working tree dirty at creation: `{str(dirty).lower()}`

## Goal

待填写。

## Environment

- Device / emulator: 待填写
- Physical size: 待填写
- Density / logical viewport: 待填写
- App version / package: 待填写
- APK: 待填写

## Acceptance Points

- [ ] 入口状态
- [ ] 核心交互
- [ ] 结果或返回状态
- [ ] 空状态 / 错误恢复（适用时）

## Steps And Evidence

| Step | Action | Expected | Screenshot / UI tree | Result |
|---:|---|---|---|---|
| 1 | 待填写 | 待填写 | 待填写 | 待填写 |

## Automated Verification

- Static analysis: 待填写
- Targeted tests: 待填写
- Full tests: 待填写
- Build: 待填写

## Findings

待填写。

## Blockers

无；如有截图或设备阻塞，必须在这里和 `screenshots/CAPTURE_BLOCKED.md` 同时记录。
"""
    (run_dir / "manifest.md").write_text(manifest, encoding="utf-8")
    print(run_dir.relative_to(REPO_ROOT).as_posix())


if __name__ == "__main__":
    main()
