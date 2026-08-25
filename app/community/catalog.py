from __future__ import annotations

from typing import Any


PILOT_PARKS: tuple[dict[str, Any], ...] = (
    {
        "id": "hangzhou-botanical-garden",
        "name": "杭州植物园",
        "area_id": "xihu",
        "area_name": "西湖区",
        "public_centroid": {"lat": 30.252, "lng": 120.118},
        "habitat_tags": ["林地", "灌木", "植物园"],
        "zones": [
            {"id": "lingfeng-entrance", "name": "灵峰入口", "habitat_tags": ["林缘", "入口"]},
            {"id": "understory-trail", "name": "林下步道", "habitat_tags": ["林下", "树冠"]},
            {"id": "aquatic-edge", "name": "水生植物区外围", "habitat_tags": ["水边", "湿地"]},
        ],
    },
    {
        "id": "xixi-wetland",
        "name": "西溪湿地",
        "area_id": "xihu",
        "area_name": "西湖区",
        "public_centroid": {"lat": 30.273, "lng": 120.061},
        "habitat_tags": ["湿地", "水网", "林地"],
        "zones": [
            {"id": "wetland-boardwalk", "name": "湿地步道", "habitat_tags": ["步道", "水边"]},
            {"id": "reed-edge", "name": "芦苇外围", "habitat_tags": ["芦苇", "浅水"]},
            {"id": "woodland-island", "name": "林地岛外围", "habitat_tags": ["林地", "灌木"]},
        ],
    },
    {
        "id": "taiziwan-park",
        "name": "太子湾公园",
        "area_id": "xihu",
        "area_name": "西湖区",
        "public_centroid": {"lat": 30.226, "lng": 120.143},
        "habitat_tags": ["城市公园", "草地", "水岸"],
        "zones": [
            {"id": "main-lawn", "name": "中心草地区", "habitat_tags": ["草地", "开阔地"]},
            {"id": "stream-trail", "name": "溪流步道", "habitat_tags": ["流水", "步道"]},
            {"id": "woodland-slope", "name": "林缘缓坡", "habitat_tags": ["林缘", "灌木"]},
        ],
    },
)

PILOT_ROUTES: tuple[dict[str, Any], ...] = (
    {
        "id": "botanical-morning-canopy",
        "park_id": "hangzhou-botanical-garden",
        "name": "清晨树冠声音路线",
        "duration_minutes": 35,
        "distance_km": 1.6,
        "age_min": 6,
        "tags": ["鸟类", "树冠", "避开水边"],
        "stops": [
            {"site_id": "hangzhou-botanical-garden:lingfeng-entrance", "minutes": 5, "mission": "先安静听三分钟，记录声音来自高处还是低处。"},
            {"site_id": "hangzhou-botanical-garden:understory-trail", "minutes": 10, "mission": "比较树冠和灌木的叫声节奏。"},
            {"site_id": "hangzhou-botanical-garden:aquatic-edge", "minutes": 5, "mission": "只在步道上倾听，记录水边与林地声音的差别。"},
        ],
    },
    {
        "id": "xixi-wetland-listening",
        "park_id": "xixi-wetland",
        "name": "湿地边缘倾听路线",
        "duration_minutes": 45,
        "distance_km": 2.0,
        "age_min": 8,
        "tags": ["蛙类", "水鸟", "全程步道"],
        "stops": [
            {"site_id": "xixi-wetland:wetland-boardwalk", "minutes": 8, "mission": "分辨水面、芦苇和树木三个方向的声音。"},
            {"site_id": "xixi-wetland:reed-edge", "minutes": 8, "mission": "记录连续鸣叫还是间隔鸣叫，不离开步道。"},
            {"site_id": "xixi-wetland:woodland-island", "minutes": 8, "mission": "比较湿地和林地的声音类型。"},
        ],
    },
    {
        "id": "taiziwan-family-short",
        "park_id": "taiziwan-park",
        "name": "城市公园亲子短路线",
        "duration_minutes": 25,
        "distance_km": 1.1,
        "age_min": 6,
        "tags": ["短路线", "草地", "鸣虫"],
        "stops": [
            {"site_id": "taiziwan-park:main-lawn", "minutes": 5, "mission": "听听开阔草地里有几种不同节奏。"},
            {"site_id": "taiziwan-park:stream-trail", "minutes": 5, "mission": "比较流水声和动物声音，不靠近水边。"},
            {"site_id": "taiziwan-park:woodland-slope", "minutes": 5, "mission": "寻找来自灌木或树冠的短促声音。"},
        ],
    },
)


def park_by_id(park_id: str | None) -> dict[str, Any] | None:
    return next((park for park in PILOT_PARKS if park["id"] == park_id), None)


def zone_by_id(park_id: str | None, zone_id: str | None) -> dict[str, Any] | None:
    park = park_by_id(park_id)
    if not park:
        return None
    return next((zone for zone in park["zones"] if zone["id"] == zone_id), None)
