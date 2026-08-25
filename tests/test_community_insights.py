from datetime import timedelta

from app.community.insights import build_daily_brief
from app.community.models import PublicationMetadata, utc_now
from app.community.repository import MemoryCommunityRepository


def _metadata(*, owner: str, observed_at, zone_id: str) -> PublicationMetadata:
    return PublicationMetadata(
        owner_id=owner,
        alias="晨风探员 123",
        area_id="xihu",
        area_name="西湖区",
        subject="乌鸫候选",
        sound_type="鸟鸣",
        observed_at=observed_at,
        duration_ms=8_000,
        adult_confirmed=True,
        public_consent=True,
        park_id="hangzhou-botanical-garden",
        zone_id=zone_id,
        site_id=f"hangzhou-botanical-garden:{zone_id}",
        sampling_mode="guided_task",
        ecology_eligible=True,
    )


def test_snapshot_compares_periods_and_explains_zone_coverage():
    repository = MemoryCommunityRepository()
    now = utc_now()
    for index in range(6):
        repository.create_post(
            _metadata(
                owner=f"device_previous_{index:02d}",
                observed_at=now - timedelta(days=9),
                zone_id="understory-trail",
            ),
            f"/previous-{index}.wav",
        )
    for index in range(8):
        repository.create_post(
            _metadata(
                owner=f"device_current_{index % 4:02d}",
                observed_at=now - timedelta(days=1 + index % 2),
                zone_id=(
                    "understory-trail" if index < 5 else "aquatic-edge"
                ),
            ),
            f"/current-{index}.wav",
        )

    snapshot = repository.ecology_snapshot(
        "hangzhou-botanical-garden", period_days=7
    )

    assert snapshot.valid_post_count == 8
    assert snapshot.previous_valid_post_count == 6
    assert snapshot.independent_observer_count == 4
    assert snapshot.observation_day_count == 2
    assert snapshot.activity_trend == "higher"
    assert snapshot.sampling_mode_counts == {"guided_task": 8}
    assert {item.zone_id: item.valid_post_count for item in snapshot.zone_summaries} == {
        "lingfeng-entrance": 0,
        "understory-trail": 5,
        "aquatic-edge": 3,
    }
    brief = build_daily_brief(snapshot)
    assert any("比上一周期更多" in fact for fact in brief.facts)
    assert any("不直接代表动物数量" in item for item in brief.possible_explanations)
