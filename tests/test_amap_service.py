from __future__ import annotations

import httpx

from app.community.amap_service import AmapMapService


def test_static_map_uses_server_key_and_caches_image():
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            content=b"\x89PNG" + b"0" * 2048,
            headers={"content-type": "image/png"},
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    service = AmapMapService(api_key="server-only-key", client=client)

    first = service.hangzhou_static_map(zoom=10)
    second = service.hangzhou_static_map(zoom=10)

    assert first.content_type == "image/png"
    assert second.content == first.content
    assert len(requests) == 1
    assert requests[0].url.params["key"] == "server-only-key"
    assert requests[0].url.params["location"] == "120.1551,30.2741"


def test_static_map_endpoint_returns_image_without_exposing_key(tmp_path, monkeypatch):
    from tests.test_community_api import _client

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            content=b"\x89PNG" + b"1" * 2048,
            headers={"content-type": "image/png"},
        )

    service = AmapMapService(
        api_key="server-only-key",
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    client = _client(tmp_path, monkeypatch, amap_map_service=service)

    response = client.get("/api/community/maps/hangzhou/static")

    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.headers["x-map-provider"] == "amap"
    assert "server-only-key" not in response.text


def test_static_map_endpoint_rejects_unsupported_zoom(tmp_path, monkeypatch):
    from tests.test_community_api import _client

    service = AmapMapService(api_key="server-only-key")
    client = _client(tmp_path, monkeypatch, amap_map_service=service)

    response = client.get("/api/community/maps/hangzhou/static", params={"zoom": 20})

    assert response.status_code == 422
