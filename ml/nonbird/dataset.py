from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

from ml.nonbird.config import NonBirdConfig


APPROVED_REVIEW_STATES = {"human_reviewed", "expert_confirmed", "approved"}
VALID_SPLITS = {"train", "validation", "test"}


@dataclass(frozen=True)
class ManifestRow:
    audio_path: Path
    labels: tuple[str, ...]
    split: str
    split_group: str
    review_status: str
    start_seconds: float | None = None
    end_seconds: float | None = None

    def accepts_window(self, start: float, end: float) -> bool:
        if self.start_seconds is None or self.end_seconds is None:
            return True
        return start < self.end_seconds and end > self.start_seconds


def load_manifest(path: Path, config: NonBirdConfig) -> list[ManifestRow]:
    base = path.parent
    rows: list[ManifestRow] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for line_number, value in enumerate(csv.DictReader(handle), start=2):
            review_status = (value.get("review_status") or "").strip()
            if review_status not in APPROVED_REVIEW_STATES:
                continue
            split = (value.get("split") or "").strip()
            if split not in VALID_SPLITS:
                raise ValueError(f"第 {line_number} 行 split 无效: {split}")
            labels = tuple(
                item.strip() for item in (value.get("labels") or "").split("|") if item.strip()
            )
            unknown = set(labels) - set(config.class_ids)
            if not labels or unknown:
                raise ValueError(f"第 {line_number} 行包含未知或空标签: {sorted(unknown)}")
            raw_path = Path((value.get("audio_path") or "").strip())
            audio_path = raw_path if raw_path.is_absolute() else (base / raw_path).resolve()
            if not audio_path.is_file():
                raise FileNotFoundError(f"第 {line_number} 行音频不存在: {audio_path}")
            split_group = (value.get("split_group") or "").strip()
            if not split_group:
                raise ValueError(f"第 {line_number} 行缺少 split_group")
            start_text = (value.get("start_seconds") or "").strip()
            end_text = (value.get("end_seconds") or "").strip()
            start = float(start_text) if start_text else None
            end = float(end_text) if end_text else None
            if (start is None) != (end is None) or (
                start is not None and (start < 0 or end <= start)
            ):
                raise ValueError(f"第 {line_number} 行有效时间段无效")
            rows.append(
                ManifestRow(
                    audio_path=audio_path,
                    labels=labels,
                    split=split,
                    split_group=split_group,
                    review_status=review_status,
                    start_seconds=start,
                    end_seconds=end,
                )
            )
    if not rows:
        raise ValueError("清单中没有已审核样本")
    group_splits: dict[str, set[str]] = {}
    for row in rows:
        group_splits.setdefault(row.split_group, set()).add(row.split)
    leaking = sorted(group for group, splits in group_splits.items() if len(splits) > 1)
    if leaking:
        raise ValueError(f"split_group 跨集合泄漏: {leaking[:5]}")
    return rows
