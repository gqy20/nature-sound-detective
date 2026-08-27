from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass

import httpx

AMAP_STATIC_MAP_URL = "https://restapi.amap.com/v3/staticmap"


class AmapMapUnavailable(RuntimeError):
    """Raised when a real map image cannot be obtained safely."""


@dataclass(frozen=True)
class StaticMapImage:
    content: bytes
    content_type: str


class AmapMapService:
    def __init__(
        self,
        *,
        api_key: str | None = None,
        client: httpx.Client | None = None,
        cache_ttl_seconds: int = 6 * 60 * 60,
    ) -> None:
        configured_key = (
            api_key if api_key is not None else os.getenv("AMAP_GEOCODE_KEY", "")
        )
        self._api_key = configured_key.strip()
        self._client = client or httpx.Client(timeout=httpx.Timeout(6.0, connect=3.0))
        self._owns_client = client is None
        self._cache_ttl_seconds = max(60, cache_ttl_seconds)
        self._cache: dict[int, tuple[float, StaticMapImage]] = {}
        self._lock = threading.Lock()

    @property
    def configured(self) -> bool:
        return bool(self._api_key)

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def hangzhou_static_map(self, *, zoom: int = 10) -> StaticMapImage:
        if not self._api_key:
            raise AmapMapUnavailable("高德地图服务尚未配置")
        zoom = max(9, min(13, zoom))
        now = time.monotonic()
        with self._lock:
            cached = self._cache.get(zoom)
            if cached is not None and cached[0] > now:
                return cached[1]

        try:
            response = self._client.get(
                AMAP_STATIC_MAP_URL,
                params={
                    "key": self._api_key,
                    "location": "120.1551,30.2741",
                    "zoom": str(zoom),
                    "size": "750*500",
                },
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise AmapMapUnavailable("高德地图暂时不可用") from exc

        content_type = response.headers.get("content-type", "").split(";", 1)[0].lower()
        if content_type not in {
            "image/png",
            "image/jpeg",
            "image/jpg",
        } or len(response.content) < 1024:
            raise AmapMapUnavailable("高德地图返回了无效图片")
        normalized_type = "image/jpeg" if content_type == "image/jpg" else content_type
        image = StaticMapImage(response.content, normalized_type)
        with self._lock:
            self._cache[zoom] = (now + self._cache_ttl_seconds, image)
        return image
