from scripts.seed_community_demo import DEMO_POSTS, validate_demo_posts


def test_demo_seed_is_balanced_and_transparent():
    validate_demo_posts()
    counts: dict[str, int] = {}
    for post in DEMO_POSTS:
        counts[post.area_id] = counts.get(post.area_id, 0) + 1
        assert "体验数据" in post.observations[0]
    assert set(counts.values()) == {2}


def test_demo_seed_mixes_waiting_and_supported_posts():
    response_counts = [len(post.responses) for post in DEMO_POSTS]
    assert 0 in response_counts
    assert any(count >= 2 for count in response_counts)
