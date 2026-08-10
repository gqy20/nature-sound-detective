from pathlib import Path

import pytest

from app.community.storage import (
    CommunityMediaUnavailable,
    LocalCommunityMediaStore,
    VercelBlobCommunityMediaStore,
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


def test_vercel_blob_store_round_trip(monkeypatch):
    calls = []

    class Result:
        url = "https://example.public.blob.vercel-storage.com/community/audio.wav"

    monkeypatch.setattr(
        "vercel.blob.put",
        lambda path, body, **kwargs: calls.append(("put", path, body, kwargs)) or Result(),
    )
    monkeypatch.setattr(
        "vercel.blob.delete",
        lambda path: calls.append(("delete", path)),
    )
    store = VercelBlobCommunityMediaStore(prefix="community")

    url = store.save("audio.wav", b"RIFFdata", "audio/wav")
    store.delete("audio.wav")

    assert url == Result.url
    assert calls[0] == (
        "put",
        "community/audio.wav",
        b"RIFFdata",
        {
            "access": "public",
            "content_type": "audio/wav",
            "add_random_suffix": False,
            "cache_control_max_age": 31_536_000,
        },
    )
    assert calls[1] == ("delete", "community/audio.wav")


def test_vercel_blob_configuration_takes_precedence(tmp_path, monkeypatch):
    monkeypatch.setenv("VERCEL_ENV", "production")
    monkeypatch.setenv("BLOB_READ_WRITE_TOKEN", "vercel_blob_token")
    monkeypatch.setenv("COMMUNITY_MEDIA_PREFIX", "competition")

    store = media_store_from_environment(tmp_path)

    assert isinstance(store, VercelBlobCommunityMediaStore)
    assert store._path("audio.wav") == "competition/audio.wav"
