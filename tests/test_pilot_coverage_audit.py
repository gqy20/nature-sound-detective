from scripts.audit_pilot_coverage import summarize_snapshot


def test_coverage_report_explains_missing_posts_observers_and_zones():
    report = summarize_snapshot(
        {
            "park_id": "hangzhou-botanical-garden",
            "valid_post_count": 2,
            "independent_observer_count": 1,
            "observation_day_count": 1,
            "data_sufficiency": "low",
            "zone_summaries": [
                {"zone_name": "灵峰入口", "valid_post_count": 2},
                {"zone_name": "林下步道", "valid_post_count": 0},
                {"zone_name": "水生植物区外围", "valid_post_count": 0},
            ],
        },
        "杭州植物园",
    )
    assert report["ready_for_medium"] is False
    assert report["missing_posts"] == 4
    assert report["missing_observers"] == 2
    assert report["empty_zones"] == ["林下步道", "水生植物区外围"]


def test_coverage_report_marks_medium_snapshot_ready():
    report = summarize_snapshot(
        {
            "park_id": "xixi-wetland",
            "valid_post_count": 6,
            "independent_observer_count": 3,
            "observation_day_count": 2,
            "data_sufficiency": "medium",
            "zone_summaries": [
                {"zone_name": "湿地步道", "valid_post_count": 2},
                {"zone_name": "芦苇外围", "valid_post_count": 2},
                {"zone_name": "林地岛外围", "valid_post_count": 2},
            ],
        },
        "西溪湿地",
    )
    assert report["ready_for_medium"] is True
    assert report["missing_posts"] == 0
    assert report["missing_observers"] == 0
