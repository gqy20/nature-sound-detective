from __future__ import annotations

import argparse
from collections import Counter
import csv
import json
from pathlib import Path


APPROVED = {"human_reviewed", "expert_confirmed", "approved"}


def audit(paths: list[Path]) -> dict[str, object]:
    rows: list[dict[str, str]] = []
    for path in paths:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows.extend(csv.DictReader(handle))
    identities = [row.get("sha256") or f"{row.get('source')}:{row.get('source_id')}" for row in rows]
    ready = [
        row
        for row in rows
        if row.get("review_status") in APPROVED
        and Path(row.get("local_path", "")).is_file()
    ]
    return {
        "candidates": len(rows),
        "ready_for_training": len(ready),
        "by_taxon": dict(Counter(row.get("taxon_id", "") for row in rows)),
        "by_license": dict(Counter(row.get("license_code", "") for row in rows)),
        "by_review_status": dict(Counter(row.get("review_status", "") for row in rows)),
        "ready_by_taxon": dict(Counter(row.get("taxon_id", "") for row in ready)),
        "missing_attribution": sum(not row.get("attribution", "").strip() for row in rows),
        "duplicate_identities": len(identities) - len(set(identities)),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="审计蛙虫候选数据的许可、审核和落盘状态")
    parser.add_argument("candidates", type=Path, nargs="+")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    report = audit(args.candidates)
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    print(rendered)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    if args.require_ready and not report["ready_for_training"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
