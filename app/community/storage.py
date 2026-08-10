from __future__ import annotations

import os
from pathlib import Path
from typing import Protocol


class CommunityMediaStore(Protocol):
    def save(self, media_name: str, payload: bytes, content_type: str) -> str: ...
    def delete(self, media_name: str) -> None: ...
    def local_path(self, media_name: str) -> Path | None: ...


class CommunityMediaUnavailable(RuntimeError):
    pass


class UnavailableCommunityMediaStore:
    def save(self, media_name: str, payload: bytes, content_type: str) -> str:
        del media_name, payload, content_type
        raise CommunityMediaUnavailable("线上声音存储尚未配置，请联系管理员")

    def delete(self, media_name: str) -> None:
        del media_name

    def local_path(self, media_name: str) -> Path | None:
        del media_name
        return None


class LocalCommunityMediaStore:
    def __init__(self, directory: Path) -> None:
        self._directory = directory

    def save(self, media_name: str, payload: bytes, content_type: str) -> str:
        del content_type
        self._directory.mkdir(parents=True, exist_ok=True)
        (self._directory / media_name).write_bytes(payload)
        return f"/api/community/media/{media_name}"

    def delete(self, media_name: str) -> None:
        (self._directory / media_name).unlink(missing_ok=True)

    def local_path(self, media_name: str) -> Path | None:
        path = self._directory / media_name
        return path if path.is_file() else None


class S3CommunityMediaStore:
    def __init__(
        self,
        *,
        endpoint_url: str,
        access_key_id: str,
        secret_access_key: str,
        bucket: str,
        public_base_url: str,
        region: str = "auto",
        prefix: str = "community",
    ) -> None:
        import boto3

        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key_id,
            aws_secret_access_key=secret_access_key,
            region_name=region,
        )
        self._bucket = bucket
        self._public_base_url = public_base_url.rstrip("/")
        self._prefix = prefix.strip("/")

    def _key(self, media_name: str) -> str:
        return f"{self._prefix}/{media_name}" if self._prefix else media_name

    def save(self, media_name: str, payload: bytes, content_type: str) -> str:
        key = self._key(media_name)
        self._client.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=payload,
            ContentType=content_type,
            CacheControl="public, max-age=31536000, immutable",
        )
        return f"{self._public_base_url}/{key}"

    def delete(self, media_name: str) -> None:
        self._client.delete_object(Bucket=self._bucket, Key=self._key(media_name))

    def local_path(self, media_name: str) -> Path | None:
        del media_name
        return None


def media_store_from_environment(local_directory: Path) -> CommunityMediaStore:
    values = {
        "endpoint_url": os.getenv("COMMUNITY_S3_ENDPOINT_URL", "").strip(),
        "access_key_id": os.getenv("COMMUNITY_S3_ACCESS_KEY_ID", "").strip(),
        "secret_access_key": os.getenv("COMMUNITY_S3_SECRET_ACCESS_KEY", "").strip(),
        "bucket": os.getenv("COMMUNITY_S3_BUCKET", "").strip(),
        "public_base_url": os.getenv("COMMUNITY_S3_PUBLIC_BASE_URL", "").strip(),
    }
    configured = [key for key, value in values.items() if value]
    if not configured:
        if os.getenv("VERCEL_ENV") == "production":
            return UnavailableCommunityMediaStore()
        return LocalCommunityMediaStore(local_directory)
    if len(configured) != len(values):
        missing = ", ".join(key for key, value in values.items() if not value)
        raise RuntimeError(f"对象存储配置不完整：{missing}")
    return S3CommunityMediaStore(
        **values,
        region=os.getenv("COMMUNITY_S3_REGION", "auto").strip() or "auto",
        prefix=os.getenv("COMMUNITY_S3_PREFIX", "community").strip("/"),
    )
