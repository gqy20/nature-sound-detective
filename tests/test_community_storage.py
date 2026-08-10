from pathlib import Path

import pytest

from app.community.storage import (
    CommunityMediaUnavailable,
    LocalCommunityMediaStore,
    media_store_from_environment,
)


def test_local_media_store_round_trip(tmp_path: Path):
    store = LocalCommunityMediaStore(tmp_path)
    url = store.save("a" * 32 + ".wav", b"RIFFdata", "audio/wav")

    assert url == f"/api/community/media/{'a' * 32}.wav"
    assert store.local_path("a" * 32 + ".wav").read_bytes() == b"RIFFdata"
    store.delete("a" * 32 + ".wav")
    assert store.local_path("a" * 32 + ".wav") is None


def test_partial_object_storage_configuration_fails_closed(tmp_path, monkeypatch):
    monkeypatch.setenv("COMMUNITY_S3_BUCKET", "sounds")
    with pytest.raises(RuntimeError, match="配置不完整"):
        media_store_from_environment(tmp_path)


def test_production_without_object_storage_rejects_uploads(tmp_path, monkeypatch):
    monkeypatch.setenv("VERCEL_ENV", "production")
    store = media_store_from_environment(tmp_path)
    with pytest.raises(CommunityMediaUnavailable):
        store.save("a" * 32 + ".wav", b"RIFFdata", "audio/wav")
