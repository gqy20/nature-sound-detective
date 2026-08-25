"""Seed transparent, idempotent demo content for the community soundscape.

The rows created here are clearly labelled as experience data. The script
never removes or updates user-created rows. Run without ``--apply`` to preview.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv


DEMO_PREFIX = "demo-2026-"
DEMO_OWNER_HASH = hashlib.sha256(b"xykw-community-demo-v1").hexdigest()


@dataclass(frozen=True)
class DemoPost:
    slug: str
    alias: str
    area_id: str
    area_name: str
    subject: str
    sound_type: str
    hours_ago: int
    audio_url: str
    duration_ms: int
    candidates: tuple[str, ...]
    observations: tuple[str, ...]
    responses: tuple[str, ...] = ()
    park_id: str | None = None
    zone_id: str | None = None

    @property
    def id(self) -> str:
        return f"{DEMO_PREFIX}{self.slug}"

    @property
    def site_id(self) -> str | None:
        if self.park_id is None or self.zone_id is None:
            return None
        return f"{self.park_id}:{self.zone_id}"


CC0_AUDIO = {
    "morning_birds": (
        "https://cdn.freesound.org/previews/578/578150_1486586-hq.mp3",
        "Freesound #578150 · CC0",
    ),
    "crows": (
        "https://cdn.freesound.org/previews/840/840818_16752880-hq.mp3",
        "Freesound #840818 · CC0",
    ),
    "rain": (
        "https://cdn.freesound.org/previews/398/398740_5923045-hq.mp3",
        "Freesound #398740 · CC0",
    ),
    "crickets": (
        "https://cdn.freesound.org/previews/529/529779_5828667-hq.mp3",
        "Freesound #529779 · CC0",
    ),
    "water": (
        "https://cdn.freesound.org/previews/582/582921_7811542-hq.mp3",
        "Freesound #582921 · CC0",
    ),
    "city": (
        "https://cdn.freesound.org/previews/818/818390_17247322-hq.mp3",
        "Freesound #818390 · CC0",
    ),
}


def _audio(key: str) -> str:
    return CC0_AUDIO[key][0]


DEMO_POSTS = (
    DemoPost(
        "xihu-morning",
        "湖畔体验员",
        "xihu",
        "西湖区",
        "体验线索 · 林间晨鸣",
        "鸟鸣",
        2,
        _audio("morning_birds"),
        12_000,
        ("乌鸫", "鹊鸲", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "树冠方向，背景有城市环境声"),
        ("乌鸫", "乌鸫", "鹊鸲"),
    ),
    DemoPost(
        "xihu-rain",
        "雨巷体验员",
        "xihu",
        "西湖区",
        "体验线索 · 荷叶雨滴",
        "雨水",
        28,
        _audio("rain"),
        10_000,
        ("雨滴", "溪流", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "连续细雨，声音节奏较均匀"),
        ("雨滴", "雨滴"),
    ),
    DemoPost(
        "shangcheng-rooftop",
        "城墙体验员",
        "shangcheng",
        "上城区",
        "体验线索 · 屋顶鸟群",
        "鸟鸣",
        5,
        _audio("crows"),
        9_000,
        ("大嘴乌鸦", "喜鹊", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "高处传来，夹杂轻微车流声"),
        (),
    ),
    DemoPost(
        "shangcheng-evening",
        "晚风体验员",
        "shangcheng",
        "上城区",
        "体验线索 · 街巷晚风",
        "城市声景",
        51,
        _audio("city"),
        11_000,
        ("风与树叶", "远处交通", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "傍晚时段，近处较安静"),
        ("远处交通",),
    ),
    DemoPost(
        "gongshu-canal",
        "运河体验员",
        "gongshu",
        "拱墅区",
        "体验线索 · 水岸回声",
        "水声",
        8,
        _audio("water"),
        8_000,
        ("水滴", "岸边回声", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "近水环境，空间回声清晰"),
        ("水滴", "岸边回声"),
    ),
    DemoPost(
        "gongshu-night",
        "桥下体验员",
        "gongshu",
        "拱墅区",
        "体验线索 · 夜间虫声",
        "虫鸣",
        76,
        _audio("crickets"),
        14_000,
        ("蟋蟀", "螽斯", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "草丛方向，持续且密集"),
        (),
    ),
    DemoPost(
        "binjiang-riverside",
        "江畔体验员",
        "binjiang",
        "滨江区",
        "体验线索 · 江风与水声",
        "水声",
        12,
        _audio("water"),
        9_000,
        ("岸边水声", "雨后滴水", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "开阔水岸，风声较明显"),
        ("岸边水声", "岸边水声", "雨后滴水"),
    ),
    DemoPost(
        "binjiang-greenway",
        "绿道体验员",
        "binjiang",
        "滨江区",
        "体验线索 · 绿道晨鸟",
        "鸟鸣",
        100,
        _audio("morning_birds"),
        13_000,
        ("乌鸫", "白头鹎", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "清晨树冠，个体距离较远"),
        ("白头鹎",),
    ),
    DemoPost(
        "yuhang-woods",
        "山林体验员",
        "yuhang",
        "余杭区",
        "体验线索 · 林下虫鸣",
        "虫鸣",
        18,
        _audio("crickets"),
        15_000,
        ("蟋蟀", "螽斯", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "林下湿润，声音来自落叶层"),
        (),
    ),
    DemoPost(
        "yuhang-after-rain",
        "苔痕体验员",
        "yuhang",
        "余杭区",
        "体验线索 · 雨后林缘",
        "雨水",
        124,
        _audio("rain"),
        10_000,
        ("叶面雨滴", "溪流", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "雨势渐弱，偶有鸟声进入"),
        ("叶面雨滴", "叶面雨滴"),
    ),
    DemoPost(
        "xiaoshan-field",
        "田野体验员",
        "xiaoshan",
        "萧山区",
        "体验线索 · 田边合鸣",
        "混合声景",
        22,
        _audio("morning_birds"),
        16_000,
        ("鸟虫合鸣", "城市背景声", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "开阔地带，多种声音重叠"),
        ("鸟虫合鸣", "鸟虫合鸣", "暂时无法判断"),
    ),
    DemoPost(
        "xiaoshan-evening",
        "潮声体验员",
        "xiaoshan",
        "萧山区",
        "体验线索 · 傍晚远声",
        "城市声景",
        148,
        _audio("city"),
        12_000,
        ("远处交通", "风与树叶", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "傍晚低频背景声较明显"),
        (),
    ),
    DemoPost(
        "botanical-lingfeng-morning",
        "灵峰体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 灵峰入口晨鸣",
        "鸟鸣",
        3,
        _audio("morning_birds"),
        12_000,
        ("乌鸫", "白头鹎", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "灵峰入口附近，声音来自林缘高处"),
        ("更像清晨树冠鸟鸣",),
        "hangzhou-botanical-garden",
        "lingfeng-entrance",
    ),
    DemoPost(
        "botanical-understory",
        "林下体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 林下短促叫声",
        "鸟鸣",
        21,
        _audio("crows"),
        9_000,
        ("喜鹊", "鸦科鸟类", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "林下步道，树冠与灌木方向都有声音"),
        (),
        "hangzhou-botanical-garden",
        "understory-trail",
    ),
    DemoPost(
        "botanical-aquatic-edge",
        "水生区体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 水生植物区水声",
        "水声",
        46,
        _audio("water"),
        10_000,
        ("流水", "水滴", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "只在外围步道倾听，背景有远处鸟鸣"),
        ("水滴", "流水"),
        "hangzhou-botanical-garden",
        "aquatic-edge",
    ),
    DemoPost(
        "xixi-boardwalk",
        "湿地步道体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 湿地步道远声",
        "混合声景",
        7,
        _audio("morning_birds"),
        14_000,
        ("水鸟", "林鸟", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "湿地步道，水面和树木方向声音重叠"),
        ("更像水面方向",),
        "xixi-wetland",
        "wetland-boardwalk",
    ),
    DemoPost(
        "xixi-reed-edge",
        "芦苇体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 芦苇外围虫声",
        "虫鸣",
        31,
        _audio("crickets"),
        15_000,
        ("蟋蟀", "螽斯", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "芦苇外围，连续鸣叫，不进入芦苇区域"),
        (),
        "xixi-wetland",
        "reed-edge",
    ),
    DemoPost(
        "xixi-woodland-island",
        "林岛体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 林地岛鸟声",
        "鸟鸣",
        55,
        _audio("crows"),
        11_000,
        ("鸦科鸟类", "喜鹊", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "林地岛外围，叫声间隔较长"),
        ("喜鹊", "鸦科鸟类"),
        "xixi-wetland",
        "woodland-island",
    ),
    DemoPost(
        "taiziwan-main-lawn",
        "草地体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 中心草地合鸣",
        "虫鸣",
        10,
        _audio("crickets"),
        13_000,
        ("鸣虫", "远处鸟鸣", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "中心草地区，多种节奏从草地边缘传来"),
        (),
        "taiziwan-park",
        "main-lawn",
    ),
    DemoPost(
        "taiziwan-stream-trail",
        "溪流体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 溪流步道水声",
        "水声",
        34,
        _audio("water"),
        9_000,
        ("流水", "水滴", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "溪流步道，留在护栏内比较水声与动物声音"),
        ("流水",),
        "taiziwan-park",
        "stream-trail",
    ),
    DemoPost(
        "taiziwan-woodland-slope",
        "林缘体验员",
        "xihu",
        "西湖区",
        "公园体验线索 · 林缘缓坡晨鸟",
        "鸟鸣",
        58,
        _audio("morning_birds"),
        12_000,
        ("白头鹎", "乌鸫", "暂时无法判断"),
        ("体验数据，不代表杭州实地记录", "林缘缓坡，短促声音来自灌木与树冠"),
        ("白头鹎", "乌鸫"),
        "taiziwan-park",
        "woodland-slope",
    ),
)


def validate_demo_posts() -> None:
    ids = [post.id for post in DEMO_POSTS]
    assert len(ids) == len(set(ids))
    assert len(DEMO_POSTS) == 21
    assert {post.area_id for post in DEMO_POSTS} == {
        "xihu",
        "shangcheng",
        "gongshu",
        "binjiang",
        "yuhang",
        "xiaoshan",
    }
    assert all("体验" in post.alias for post in DEMO_POSTS)
    assert all(500 <= post.duration_ms <= 20_000 for post in DEMO_POSTS)
    park_posts = [post for post in DEMO_POSTS if post.park_id is not None]
    assert len(park_posts) == 9
    assert all(post.area_id == "xihu" for post in park_posts)
    assert all(post.site_id is not None for post in park_posts)
    assert {
        (post.park_id, post.zone_id) for post in park_posts
    } == {
        ("hangzhou-botanical-garden", "lingfeng-entrance"),
        ("hangzhou-botanical-garden", "understory-trail"),
        ("hangzhou-botanical-garden", "aquatic-edge"),
        ("xixi-wetland", "wetland-boardwalk"),
        ("xixi-wetland", "reed-edge"),
        ("xixi-wetland", "woodland-island"),
        ("taiziwan-park", "main-lawn"),
        ("taiziwan-park", "stream-trail"),
        ("taiziwan-park", "woodland-slope"),
    }


def seed(database_url: str, *, apply: bool) -> None:
    import psycopg

    validate_demo_posts()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    with psycopg.connect(database_url) as connection, connection.cursor() as cursor:
        cursor.execute(
            "SELECT area_id, count(*) FROM community_posts "
            "WHERE status <> 'withdrawn' GROUP BY area_id ORDER BY area_id"
        )
        current = dict(cursor.fetchall())
        print("Current public rows:", current or "none")
        park_count = sum(post.park_id is not None for post in DEMO_POSTS)
        print(
            f"Demo plan: {len(DEMO_POSTS)} posts across 6 districts "
            f"({park_count} park-zone posts)"
        )
        if not apply:
            print("Preview only. Re-run with --apply to write demo rows.")
            return

        for post in DEMO_POSTS:
            observed_at = now - timedelta(hours=post.hours_ago)
            created_at = observed_at + timedelta(minutes=35)
            status = "community_supported" if len(post.responses) >= 2 else "published_unverified"
            model_snapshot = {
                "demo": True,
                "disclosure": "比赛体验数据，不代表杭州实地记录",
                "audio_source": next(
                    credit for url, credit in CC0_AUDIO.values() if url == post.audio_url
                ),
            }
            cursor.execute(
                """INSERT INTO community_posts
                   (id, owner_hash, alias, area_id, area_name, subject, sound_type,
                    observed_at, created_at, audio_url, duration_ms, candidate_names,
                    field_observations, model_snapshot, status, review_status,
                    park_id, zone_id, site_id, sampling_mode, sampling_effort,
                    audio_quality, ecology_eligible)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s)
                   ON CONFLICT (id) DO UPDATE SET
                     alias=EXCLUDED.alias, area_id=EXCLUDED.area_id,
                     area_name=EXCLUDED.area_name, subject=EXCLUDED.subject,
                     sound_type=EXCLUDED.sound_type, observed_at=EXCLUDED.observed_at,
                     created_at=EXCLUDED.created_at, audio_url=EXCLUDED.audio_url,
                     duration_ms=EXCLUDED.duration_ms,
                     candidate_names=EXCLUDED.candidate_names,
                     field_observations=EXCLUDED.field_observations,
                     model_snapshot=EXCLUDED.model_snapshot, status=EXCLUDED.status,
                     review_status=EXCLUDED.review_status,
                     park_id=EXCLUDED.park_id, zone_id=EXCLUDED.zone_id,
                     site_id=EXCLUDED.site_id,
                     sampling_mode=EXCLUDED.sampling_mode,
                     sampling_effort=EXCLUDED.sampling_effort,
                     audio_quality=EXCLUDED.audio_quality,
                     ecology_eligible=false, withdrawn_at=NULL""",
                (
                    post.id,
                    DEMO_OWNER_HASH,
                    post.alias,
                    post.area_id,
                    post.area_name,
                    post.subject,
                    post.sound_type,
                    observed_at,
                    created_at,
                    post.audio_url,
                    post.duration_ms,
                    json.dumps(
                        [name for name in post.candidates if name != "暂时无法判断"],
                        ensure_ascii=False,
                    ),
                    json.dumps(post.observations, ensure_ascii=False),
                    json.dumps(model_snapshot, ensure_ascii=False),
                    status,
                    "not_requested",
                    post.park_id,
                    post.zone_id,
                    post.site_id,
                    "guided_task" if post.park_id else "opportunistic",
                    json.dumps(
                        {
                            "source": "competition_demo",
                            "virtual": True,
                        }
                    ),
                    json.dumps(
                        {"usable": False, "reason": "competition_demo"},
                        ensure_ascii=False,
                    ),
                    False,
                ),
            )
            cursor.execute(
                """INSERT INTO community_consents
                   (post_id, adult_confirmed, public_consent, review_consent)
                   VALUES (%s,true,true,false)
                   ON CONFLICT (post_id) DO UPDATE SET
                     adult_confirmed=true, public_consent=true, review_consent=false""",
                (post.id,),
            )
            cursor.execute(
                "DELETE FROM community_responses WHERE post_id=%s AND responder_hash LIKE 'demo_responder_%%'",
                (post.id,),
            )
            for index, choice in enumerate(post.responses):
                cursor.execute(
                    """INSERT INTO community_responses
                       (id, post_id, responder_hash, choice, also_heard, key_second)
                       VALUES (%s,%s,%s,%s,%s,%s)""",
                    (
                        f"{post.id}-response-{index + 1}",
                        post.id,
                        f"demo_responder_{index + 1}",
                        choice,
                        index == 0,
                        min(2 + index * 3, post.duration_ms // 1000),
                    ),
                )

        connection.commit()
        cursor.execute(
            "SELECT area_id, post_count, waiting_count FROM community_area_summaries "
            "ORDER BY area_id"
        )
        print("Seeded summaries:", cursor.fetchall())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write the demo rows")
    args = parser.parse_args()
    load_dotenv()
    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        raise SystemExit("DATABASE_URL is not configured")
    seed(database_url, apply=args.apply)


if __name__ == "__main__":
    main()
