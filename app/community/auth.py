from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import os
import time
from collections import defaultdict, deque
from dataclasses import dataclass
from threading import RLock


class InvalidCommunityToken(ValueError):
    pass


def _encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


@dataclass(frozen=True)
class CommunitySession:
    token: str
    expires_at: int


class CommunityAuth:
    def __init__(self, secret: str, *, token_ttl_seconds: int = 30 * 24 * 3600) -> None:
        if len(secret) < 32:
            raise ValueError("COMMUNITY_AUTH_SECRET 至少需要 32 个字符")
        self._secret = secret.encode("utf-8")
        self._token_ttl_seconds = token_ttl_seconds

    @classmethod
    def from_environment(cls) -> "CommunityAuth":
        secret = os.getenv("COMMUNITY_AUTH_SECRET", "").strip()
        if not secret:
            if os.getenv("VERCEL_ENV") == "production":
                raise RuntimeError("生产环境缺少 COMMUNITY_AUTH_SECRET")
            secret = "xykw-local-development-community-secret"
        return cls(secret)

    def issue(self, device_id: str, *, now: int | None = None) -> CommunitySession:
        timestamp = int(time.time() if now is None else now)
        subject = hmac.new(
            self._secret,
            f"device:{device_id}".encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        expires_at = timestamp + self._token_ttl_seconds
        payload = _encode(
            json.dumps(
                {"sub": subject, "iat": timestamp, "exp": expires_at},
                separators=(",", ":"),
            ).encode("utf-8")
        )
        signature = _encode(
            hmac.new(self._secret, f"v1.{payload}".encode("ascii"), hashlib.sha256).digest()
        )
        return CommunitySession(token=f"v1.{payload}.{signature}", expires_at=expires_at)

    def verify(self, authorization: str | None, *, now: int | None = None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise InvalidCommunityToken("缺少匿名访问令牌")
        token = authorization.removeprefix("Bearer ").strip()
        try:
            version, payload, signature = token.split(".")
            if version != "v1":
                raise ValueError
            expected = hmac.new(
                self._secret,
                f"v1.{payload}".encode("ascii"),
                hashlib.sha256,
            ).digest()
            if not hmac.compare_digest(expected, _decode(signature)):
                raise ValueError
            values = json.loads(_decode(payload))
            subject = values["sub"]
            expires_at = int(values["exp"])
        except (
            binascii.Error,
            KeyError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
        ) as exc:
            raise InvalidCommunityToken("匿名访问令牌无效") from exc
        timestamp = int(time.time() if now is None else now)
        if expires_at <= timestamp:
            raise InvalidCommunityToken("匿名访问令牌已过期")
        if not isinstance(subject, str) or len(subject) != 64:
            raise InvalidCommunityToken("匿名访问令牌无效")
        return subject


class InMemoryRateLimiter:
    """Small-instance guard; production gateways should add a distributed limit too."""

    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = RLock()

    def allow(
        self,
        key: str,
        *,
        limit: int,
        window_seconds: int,
        now: float | None = None,
    ) -> bool:
        timestamp = time.monotonic() if now is None else now
        cutoff = timestamp - window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] <= cutoff:
                events.popleft()
            if len(events) >= limit:
                return False
            events.append(timestamp)
            return True
