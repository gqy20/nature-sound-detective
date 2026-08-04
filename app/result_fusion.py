from __future__ import annotations

import re
from typing import Any


ALLOWED_SOUND_TYPES = {
    "鸟类鸣叫", "蛙类鸣叫", "昆虫鸣叫", "雨水", "流水", "风和树叶",
    "人声", "脚步", "交通或机械噪声", "其他", "无法判断",
}

CONFIDENCE_RANK = {"low": 0, "medium": 1, "high": 2}

SAFE_CARDS = {
    "鸟类鸣叫": (
        "树梢传来的歌声",
        "这段录音里比较明显的是鸟儿的叫声。不同鸟类会用声音联系同伴、提醒危险或表达自己的位置，我们可以先记下节奏，再远远观察。",
        "安静听一听，这个声音每隔多久会重复一次？",
    ),
    "蛙类鸣叫": (
        "池边的节奏",
        "这段录音里比较明显的是蛙类的叫声。蛙类常在温暖、潮湿的环境中发声，我们可以只用耳朵寻找方向，不靠近或触碰它们。",
        "你能站在安全的地方，数一数十秒里叫了几次吗？",
        "在湿滑区域观察时请和大人同行，并与水边保持距离。",
    ),
    "昆虫鸣叫": (
        "草丛里的小歌手",
        "这段录音里比较明显的是昆虫鸣叫。许多昆虫会用有节奏的声音传递信息，我们可以寻找重复规律，但不要拨动草叶或打扰它们。",
        "闭上眼睛听一听，这个声音的节奏会不会重复？",
    ),
    "雨水": (
        "雨点的节拍",
        "这段录音里比较明显的是雨声。雨滴落在树叶、泥土和屋檐上会产生不同音色，可以比较它们声音的轻重和快慢。",
        "听一听，雨点落在不同表面时有什么区别？",
        "雨天观察请注意防滑，并远离雷电和积水区域。",
    ),
    "流水": (
        "流动的声音",
        "这段录音里比较明显的是流水声。水流速度、河床材料和周围地形都会改变声音，我们可以在安全距离外比较它的强弱。",
        "你觉得水声是连续的，还是会一阵一阵变化？",
        "在水边倾听时请和大人同行，并与湿滑岸边保持距离。",
    ),
    "风和树叶": (
        "风经过树林",
        "这段录音里比较明显的是风和树叶的声音。风吹过不同大小、不同形状的叶片，会形成轻重不一的沙沙声。",
        "听一听，风声是一阵一阵的，还是一直保持相同强度？",
    ),
    "交通或机械噪声": (
        "城市里的背景声",
        "这段录音里比较明显的是交通或机械声。它们可能盖住较轻的自然声音，可以换一个更安静的位置，再比较前后录音。",
        "离开噪声源一段距离后，你还能听到哪些更轻的声音？",
        "观察时请在人行区域活动，并与道路和设备保持安全距离。",
    ),
    "无法判断": (
        "再听一次",
        "这段录音里的线索还不够清楚，暂时不能可靠判断声音类别。换一个更安静的位置、靠近目标声源一些，再录一小段可能更容易分辨。",
        "下一次录音时，你准备怎样减少周围的干扰声？",
    ),
}


def _sound_list(value: Any) -> list[str]:
    items = value if isinstance(value, list) else [value]
    result: list[str] = []
    for item in items:
        name = str(item).strip()
        if name in ALLOWED_SOUND_TYPES and name not in result:
            result.append(name)
    return result


def _capped_confidence(value: Any, cap: str = "medium") -> str:
    confidence = str(value).lower()
    if confidence not in CONFIDENCE_RANK:
        confidence = "low"
    return confidence if CONFIDENCE_RANK[confidence] <= CONFIDENCE_RANK[cap] else cap


def _safe_card(primary: str) -> dict[str, str]:
    default_safety = "户外观察请和大人同行，只倾听和记录，不追逐或触摸动物。"
    title, explanation, question, *safety = SAFE_CARDS.get(primary, SAFE_CARDS["无法判断"])
    return {
        "title": title,
        "explanation": explanation,
        "question": question,
        "safety_note": safety[0] if safety else default_safety,
    }


def fuse_results(
    qwen: dict[str, Any],
    birdnet: dict[str, Any],
    nonbird: dict[str, Any] | None = None,
) -> dict[str, Any]:
    nonbird = nonbird or {"model": None, "detections": [], "available": False}
    sound_types = _sound_list(qwen.get("sound_types", []))
    possible_sound_types = _sound_list(qwen.get("possible_sound_types", []))
    requested_primary = str(qwen.get("primary_sound_type", "")).strip()
    primary = requested_primary if requested_primary in sound_types else (sound_types[0] if sound_types else "无法判断")
    for item in sound_types:
        if item != primary and item not in possible_sound_types:
            possible_sound_types.append(item)
    sound_types = [primary]
    strong_birds = [
        item for item in birdnet.get("detections", []) if item["confidence"] >= 0.25
    ]
    strong_nonbirds = [
        item for item in nonbird.get("detections", []) if item.get("confidence", 0) >= 0.5
    ]
    specialist_candidates = [
        *[("鸟类鸣叫", item) for item in strong_birds],
        *[
            ("蛙类鸣叫" if item.get("category_id") == "frog" else "昆虫鸣叫", item)
            for item in strong_nonbirds
            if item.get("category_id") in {"frog", "insect"}
        ],
    ]
    specialist_candidates.sort(key=lambda pair: pair[1]["confidence"], reverse=True)
    if specialist_candidates and specialist_candidates[0][0] not in sound_types:
        if primary != "无法判断":
            possible_sound_types.append(primary)
        primary = specialist_candidates[0][0]
        sound_types = [primary]
    possible_sound_types = [
        item for item in possible_sound_types if item != primary and item != "无法判断"
    ]
    card = _safe_card(primary)
    question = card["question"]
    if re.search(r"拨开|翻开|触摸|抓住|抓取|追逐|靠近|伸手", question):
        question = "你能站在原地安静听听，数一数这个声音重复了几次吗？"
    evidence = qwen.get("evidence", [])
    if not isinstance(evidence, list):
        evidence = [str(evidence)]
    confidence = _capped_confidence(qwen.get("confidence_level", "low"))
    if primary == "无法判断":
        confidence = "low"
    elif primary == "鸟类鸣叫" and strong_birds:
        best_bird = max(item["confidence"] for item in strong_birds)
        confidence = "high" if best_bird >= 0.5 else "medium"
    elif primary in {"蛙类鸣叫", "昆虫鸣叫"} and strong_nonbirds:
        best_nonbird = max(item["confidence"] for item in strong_nonbirds)
        confidence = "high" if best_nonbird >= 0.75 else "medium"
    detected_sound_types = list(sound_types)
    for sound_type, _ in specialist_candidates:
        if sound_type not in detected_sound_types:
            detected_sound_types.append(sound_type)
    normalized_detections = [
        {
            "category_id": "bird",
            "name_zh": "鸟类鸣叫",
            "confidence": item["confidence"],
            "model": birdnet.get("model"),
            "intervals": [{"start": item.get("start_seconds", 0), "end": item.get("end_seconds", 0)}],
            "specific_species": {
                "name_zh": item.get("name_zh", ""),
                "scientific_name": str(item.get("label", "")).split("_", 1)[0] or None,
            },
        }
        for item in strong_birds
    ] + [
        {
            "category_id": item.get("category_id", "unknown"),
            "name_zh": "蛙类鸣叫" if item.get("category_id") == "frog" else "昆虫鸣叫",
            "confidence": item["confidence"],
            "model": nonbird.get("model"),
            "intervals": [{"start": item.get("start_seconds", 0), "end": item.get("end_seconds", 0)}],
            "specific_species": (
                {
                    "name_zh": item.get("name_zh", ""),
                    "scientific_name": item.get("scientific_name"),
                    "taxonomy_id": item.get("taxon_id"),
                }
                if item.get("scientific_name")
                else None
            ),
        }
        for item in strong_nonbirds
    ]
    normalized_detections.sort(key=lambda item: item["confidence"], reverse=True)
    return {
        "sound_types": sound_types or ["无法判断"],
        "primary_sound_type": primary,
        "detected_sound_types": detected_sound_types,
        "possible_sound_types": possible_sound_types,
        "dominant_sound": primary,
        "confidence_level": confidence,
        "possible_species": qwen.get("possible_species", []) if isinstance(qwen.get("possible_species", []), list) else [],
        "bird_species": strong_birds,
        "nonbird_species": strong_nonbirds,
        "detections": normalized_detections,
        "evidence": evidence,
        "uncertainty": qwen.get("uncertainty", ""),
        "card": {**card, "question": question},
        "models": {
            "general_audio": qwen.get("model"),
            "bird_species": birdnet.get("model"),
            "bird_scope": birdnet.get("scope"),
            "nonbird_species": nonbird.get("model"),
            "nonbird_available": bool(nonbird.get("available")),
        },
        "usage": qwen.get("usage"),
    }
