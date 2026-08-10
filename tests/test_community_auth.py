import pytest

from app.community.auth import CommunityAuth, InMemoryRateLimiter, InvalidCommunityToken


def test_session_token_is_stable_for_identity_and_rejects_tampering():
    auth = CommunityAuth("test-community-secret-with-32-characters", token_ttl_seconds=60)
    first = auth.issue("device_example_123456", now=100)
    second = auth.issue("device_example_123456", now=101)

    assert auth.verify(f"Bearer {first.token}", now=120) == auth.verify(
        f"Bearer {second.token}", now=120
    )

    tampered = f"{first.token[:-1]}x"
    with pytest.raises(InvalidCommunityToken):
        auth.verify(f"Bearer {tampered}", now=120)


def test_rate_limiter_uses_a_sliding_window():
    limiter = InMemoryRateLimiter()
    assert limiter.allow("publish:one", limit=2, window_seconds=10, now=0)
    assert limiter.allow("publish:one", limit=2, window_seconds=10, now=1)
    assert not limiter.allow("publish:one", limit=2, window_seconds=10, now=2)
    assert limiter.allow("publish:one", limit=2, window_seconds=10, now=11)
