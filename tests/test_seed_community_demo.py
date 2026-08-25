from scripts.seed_community_demo import DEMO_POSTS, validate_demo_posts


def test_demo_seed_is_balanced_and_transparent():
    validate_demo_posts()
    counts: dict[str, int] = {}
    for post in DEMO_POSTS:
        counts[post.area_id] = counts.get(post.area_id, 0) + 1
        assert "体验数据" in post.observations[0]
    assert all(count >= 2 for count in counts.values())
    assert counts["xihu"] == 11
    assert all(count == 2 for area, count in counts.items() if area != "xihu")


def test_demo_seed_mixes_waiting_and_supported_posts():
    response_counts = [len(post.responses) for post in DEMO_POSTS]
    assert 0 in response_counts
    assert any(count >= 2 for count in response_counts)


def test_demo_seed_covers_every_pilot_park_zone_without_ecology_claims():
    park_posts = [post for post in DEMO_POSTS if post.park_id is not None]
    assert len(park_posts) == 9
    assert len({post.site_id for post in park_posts}) == 9
    assert {post.park_id for post in park_posts} == {
        "hangzhou-botanical-garden",
        "xixi-wetland",
        "taiziwan-park",
    }
    assert all(post.observations[0] == "体验数据，不代表杭州实地记录" for post in park_posts)
