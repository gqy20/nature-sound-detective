from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.data_sources.candidates import write_candidates


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="将主办方虫蛙标准声登记为训练参考候选")
    parser.add_argument(
        "--standard-root",
        type=Path,
        default=Path("data/interim/challenge_2026_standard_48k_v2"),
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path("ml/configs/challenge_2026_species.json"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/metadata/challenge_2026_official_nonbird_candidates.csv"),
    )
    args = parser.parse_args()
    classes = json.loads(args.catalog.read_text(encoding="utf-8"))["classes"]
    targets = [row for row in classes if row["category_id"] in {"insect", "frog"}]
    rows: list[dict[str, object]] = []
    for category_folder in ("虫", "蛙"):
        for species_dir in sorted((args.standard_root / category_folder).iterdir()):
            if not species_dir.is_dir():
                continue
            target = next(
                (
                    row
                    for row in targets
                    if species_dir.name == row["name_zh"] or species_dir.name in row.get("aliases", [])
                ),
                None,
            )
            if target is None:
                raise ValueError(f"标准声物种不在目录中：{species_dir.name}")
            for audio in sorted(species_dir.glob("*.wav")):
                sha256 = digest(audio)
                rows.append(
                    {
                        "source": "shengshengbuxi_2026_official",
                        "source_id": f"official_{sha256[:16]}",
                        "taxon_id": target["taxon_id"],
                        "scientific_name": target["scientific_name"],
                        "name_zh": target["name_zh"],
                        "category_id": target["category_id"],
                        "source_url": "organizer-provided challenge package",
                        "media_url": "",
                        "license_code": "ORGANIZER_PROVIDED",
                        "license_url": "",
                        "commercial_compatible": False,
                        "attribution": "生声不息AI挑战赛项目组",
                        "quality_grade": "official_reference",
                        "split_hint": "test",
                        "split_group": f"official_source_{sha256}",
                        "local_path": str(audio.resolve()),
                        "sha256": sha256,
                        "review_status": "official_reference",
                        "reviewer": "organizer",
                        "review_notes": "官方标准声；同一源录音切片不得跨训练、验证和测试集。",
                    }
                )
    write_candidates(rows, args.output)
    print(f"wrote {len(rows)} official non-bird references to {args.output}")


if __name__ == "__main__":
    main()
