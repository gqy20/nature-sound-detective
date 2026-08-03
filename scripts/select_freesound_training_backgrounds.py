from __future__ import annotations

import argparse
import csv
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import license_is_usable, normalize_license, write_candidates


APPROVED = {"human_reviewed", "expert_confirmed", "approved"}


def select_backgrounds(path: Path, *, commercial_only: bool) -> list[dict[str, object]]:
    selected: list[dict[str, object]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if row.get("review_status", "").strip() not in APPROVED:
                continue
            reviewed_class = (row.get("human_final_class") or row.get("reviewed_class") or "").strip()
            contains_speech = (row.get("human_contains_speech") or row.get("contains_speech") or "").strip()
            if reviewed_class != "background" or contains_speech == "yes":
                continue
            license_info = normalize_license(row.get("license") or row.get("license_code"))
            code = str(license_info["license_code"])
            if not license_is_usable(code):
                continue
            if commercial_only and not license_info["commercial_compatible"]:
                continue
            sound_id = row.get("freesound_id", "")
            selected.append(
                {
                    "source": row.get("source", "freesound"),
                    "source_id": f"freesound_{sound_id}",
                    "taxon_id": "background",
                    "name_zh": "背景或未知声音",
                    "category_id": "background",
                    "source_url": row.get("sound_url", ""),
                    "media_url": row.get("preview_url", ""),
                    **license_info,
                    "attribution": row.get("attribution_text", ""),
                    "quality_grade": "human_reviewed",
                    "split_group": f"freesound_{sound_id}",
                    "local_path": row.get("local_path", ""),
                    "sha256": row.get("preview_sha256", ""),
                    "review_status": row["review_status"],
                    "review_notes": row.get("human_review_notes") or row.get("review_notes", ""),
                }
            )
    return selected


def main() -> None:
    parser = argparse.ArgumentParser(description="将已人工审核的 Freesound 背景转换为统一候选")
    parser.add_argument("input", type=Path, nargs="?", default=Path("data/metadata/freesound_review_queue.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/metadata/freesound_background_candidates.csv"))
    parser.add_argument("--commercial-only", action="store_true")
    args = parser.parse_args()
    rows = select_backgrounds(args.input, commercial_only=args.commercial_only)
    write_candidates(rows, args.output)
    print(f"wrote {len(rows)} reviewed background candidates to {args.output}")


if __name__ == "__main__":
    main()
