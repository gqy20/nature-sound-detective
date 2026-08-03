import json

from scripts.build_feedback_review_manifest import build_rows


def test_feedback_manifest_requires_consent_and_deduplicates(tmp_path):
    audio = tmp_path / "audio.wav"
    audio.write_bytes(b"same audio")
    consented = {
        "id": "feedback-1",
        "recording_id": "rec-1",
        "decision": "wrong",
        "corrected_taxon_id": "other_frog",
        "consent_to_retain_audio": True,
        "retained_audio_path": str(audio),
    }
    declined = {**consented, "id": "feedback-2", "consent_to_retain_audio": False}
    (tmp_path / "one.json").write_text(json.dumps(consented), encoding="utf-8")
    (tmp_path / "two.json").write_text(json.dumps(declined), encoding="utf-8")
    rows = build_rows([tmp_path])
    assert len(rows) == 1
    assert rows[0]["taxon_id"] == "other_frog"
    assert rows[0]["review_status"] == "pending"
    assert rows[0]["license_code"] == "USER-CONSENT"
