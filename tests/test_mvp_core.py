from app.pipeline import fuse_results
from app.qwen_service import _parse_json


def test_parse_json_removes_markdown_fence():
    assert _parse_json('```json\n{"sound_types":["蛙类鸣叫"]}\n```')["sound_types"] == ["蛙类鸣叫"]


def test_birdnet_detection_adds_bird_sound_type():
    qwen = {
        "sound_types": ["风和树叶"],
        "dominant_sound": "风和树叶",
        "confidence_level": "medium",
        "model": "qwen-test",
    }
    birdnet = {
        "model": "birdnet-test",
        "scope": "test",
        "detections": [{"name_zh": "乌鸫", "confidence": 0.72}],
    }
    result = fuse_results(qwen, birdnet)
    assert result["sound_types"] == ["鸟类鸣叫"]
    assert result["possible_sound_types"] == ["风和树叶"]
    assert result["bird_species"][0]["name_zh"] == "乌鸫"


def test_low_birdnet_score_is_not_shown():
    qwen = {"sound_types": ["昆虫鸣叫"], "model": "qwen-test"}
    birdnet = {
        "model": "birdnet-test",
        "scope": "test",
        "detections": [{"name_zh": "乌鸫", "confidence": 0.1}],
    }
    result = fuse_results(qwen, birdnet)
    assert result["bird_species"] == []


def test_intrusive_observation_question_is_replaced():
    qwen = {
        "sound_types": ["昆虫鸣叫"],
        "observation_question": "你能拨开草叶抓住它看看吗？",
        "model": "qwen-test",
    }
    birdnet = {"model": "birdnet-test", "scope": "test", "detections": []}
    result = fuse_results(qwen, birdnet)
    assert "拨开" not in result["card"]["question"]
    assert "抓" not in result["card"]["question"]


def test_general_model_high_confidence_is_capped_until_verified():
    qwen = {
        "sound_types": ["昆虫鸣叫"],
        "primary_sound_type": "昆虫鸣叫",
        "confidence_level": "high",
        "model": "qwen-test",
    }
    birdnet = {"model": "birdnet-test", "scope": "test", "detections": []}
    result = fuse_results(qwen, birdnet)
    assert result["confidence_level"] == "medium"


def test_secondary_sound_does_not_enter_child_card():
    qwen = {
        "sound_types": ["风和树叶", "流水"],
        "primary_sound_type": "风和树叶",
        "confidence_level": "high",
        "child_explanation": "这里还有一条小河。",
        "safety_note": "不要靠近水边。",
        "model": "qwen-test",
    }
    birdnet = {"model": "birdnet-test", "scope": "test", "detections": []}
    result = fuse_results(qwen, birdnet)
    assert result["sound_types"] == ["风和树叶"]
    assert result["possible_sound_types"] == ["流水"]
    assert "小河" not in result["card"]["explanation"]
    assert "水边" not in result["card"]["safety_note"]


def test_strong_birdnet_detection_can_mark_result_high_confidence():
    qwen = {
        "sound_types": ["风和树叶"],
        "confidence_level": "low",
        "model": "qwen-test",
    }
    birdnet = {
        "model": "birdnet-test",
        "scope": "test",
        "detections": [{"name_zh": "乌鸫", "confidence": 0.72}],
    }
    result = fuse_results(qwen, birdnet)
    assert result["primary_sound_type"] == "鸟类鸣叫"
    assert result["confidence_level"] == "high"


def test_nonbird_detector_adds_specific_insect_without_hiding_bird_candidate():
    qwen = {
        "sound_types": ["风和树叶"],
        "primary_sound_type": "风和树叶",
        "confidence_level": "low",
        "model": "qwen-test",
    }
    birdnet = {
        "model": "birdnet-test",
        "scope": "杭州200种鸟",
        "detections": [{"name_zh": "乌鸫", "confidence": 0.55}],
    }
    nonbird = {
        "model": "nonbird-test",
        "available": True,
        "detections": [
            {
                "category_id": "insect",
                "taxon_id": "cryptotympana_atrata",
                "name_zh": "黑蚱蝉",
                "scientific_name": "Cryptotympana atrata",
                "confidence": 0.82,
                "start_seconds": 3,
                "end_seconds": 6,
            }
        ],
    }
    result = fuse_results(qwen, birdnet, nonbird)
    assert result["primary_sound_type"] == "昆虫鸣叫"
    assert result["detected_sound_types"] == ["昆虫鸣叫", "鸟类鸣叫"]
    assert result["nonbird_species"][0]["name_zh"] == "黑蚱蝉"
    assert {item["category_id"] for item in result["detections"]} == {"bird", "insect"}
