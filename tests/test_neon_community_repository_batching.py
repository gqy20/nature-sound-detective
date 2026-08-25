from datetime import datetime, timezone

from app.community.repository import NeonCommunityRepository


def _post_row(post_id: str):
    now = datetime.now(timezone.utc)
    return {
        "id": post_id,
        "owner_hash": "owner-hash",
        "alias": "晨风探员 123",
        "area_id": "xihu",
        "area_name": "西湖区",
        "subject": "乌鸫候选",
        "sound_type": "鸟鸣",
        "observed_at": now,
        "created_at": now,
        "audio_url": f"/media/{post_id}.wav",
        "duration_ms": 8_000,
        "candidate_names": ["乌鸫"],
        "field_observations": ["树冠"],
        "status": "published_unverified",
        "review_status": "not_requested",
        "response_count": 0,
        "response_summary": {},
        "park_id": "hangzhou-botanical-garden",
        "zone_id": "understory-trail",
        "site_id": "hangzhou-botanical-garden:understory-trail",
        "sampling_mode": "guided_task",
        "sampling_effort": {},
        "audio_quality": {"usable": True},
        "ecology_eligible": True,
    }


class _FakeCursor:
    def __init__(self, queries, post_rows, media_rows):
        self.queries = queries
        self.post_rows = post_rows
        self.media_rows = media_rows
        self.result = []

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def execute(self, sql, params=None):
        self.queries.append((" ".join(sql.split()), params))
        self.result = (
            self.media_rows if "community_media_assets" in sql else self.post_rows
        )

    def fetchall(self):
        return self.result


class _FakeConnection:
    def __init__(self, queries, post_rows, media_rows):
        self.queries = queries
        self.post_rows = post_rows
        self.media_rows = media_rows

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def cursor(self):
        return _FakeCursor(self.queries, self.post_rows, self.media_rows)


def test_neon_list_batches_media_for_all_posts():
    queries = []
    post_rows = [_post_row(f"post-{index}") for index in range(5)]
    media_rows = [
        {
            "id": "asset-1",
            "post_id": "post-3",
            "media_type": "video",
            "source_type": "composed",
            "storage_url": "/media/story.mp4",
            "thumbnail_url": None,
            "provider": "story-pipeline",
            "model": None,
            "moderation_status": "approved",
        }
    ]
    repository = object.__new__(NeonCommunityRepository)
    repository._connection = lambda: _FakeConnection(  # type: ignore[method-assign]
        queries, post_rows, media_rows
    )

    posts = repository.list_posts(area_id=None, requester_id=None)

    assert len(posts) == 5
    assert len(queries) == 2
    assert "community_public_posts" in queries[0][0]
    assert "post_id = ANY" in queries[1][0]
    assert queries[1][1] == ([f"post-{index}" for index in range(5)],)
    assert posts[3].media_assets[0].url == "/media/story.mp4"
