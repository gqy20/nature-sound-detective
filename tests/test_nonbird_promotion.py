import csv
from scripts.compare_nonbird_models import promotion_report
from scripts.promote_reviewed_feedback import promote


def test_promoted_feedback_is_train_only_and_requires_human_review(tmp_path):
    audio = tmp_path / "feedback.wav"
    audio.write_bytes(b"audio")
    base = tmp_path / "base.csv"
    base.write_text(
        "audio_path,labels,split,split_group,review_status,start_seconds,end_seconds,source_dataset,source_recording_id,source_url,license,commercial_compatible,reviewer\n"
        "feedback.wav,background,test,base,source_curated,,,base,base-1,,CC0,true,\n",
        encoding="utf-8",
    )
    candidates = tmp_path / "feedback.csv"
    fields = [
        "source_id", "taxon_id", "local_path", "split_group", "review_status", "reviewer", "valid_intervals"
    ]
    with candidates.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerow(
            {
                "source_id": "feedback-1",
                "taxon_id": "other_frog",
                "local_path": str(audio),
                "split_group": "feedback:rec-1",
                "review_status": "human_reviewed",
                "reviewer": "reviewer",
                "valid_intervals": "",
            }
        )
        writer.writerow(
            {
                "source_id": "pending",
                "taxon_id": "other_frog",
                "local_path": str(audio),
                "split_group": "feedback:pending",
                "review_status": "pending",
                "reviewer": "",
                "valid_intervals": "",
            }
        )
    rows, appended = promote(base, candidates, output=tmp_path / "combined.csv")
    assert appended == 1
    promoted = next(row for row in rows if row.get("source_dataset") == "user_feedback")
    assert promoted["split"] == "train"


def test_promotion_gate_blocks_regression_and_background_false_positives():
    baseline = {
        "test_metrics": {
            "cryptotympana_atrata": {"f1": 0.95},
            "polypedates_braueri": {"f1": 0.91},
        }
    }
    candidate = {
        "metrics": {
            "cryptotympana_atrata": {"precision": 0.95, "f1": 0.7},
            "polypedates_braueri": {"precision": 0.95, "f1": 0.9},
        }
    }
    stress = {"conditions": {"background_clean": {"false_positive_rate": 0.1}}}
    report = promotion_report(baseline, candidate, stress)
    assert report["approved"] is False
    assert len(report["reasons"]) == 2
