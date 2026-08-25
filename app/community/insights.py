from __future__ import annotations

from app.community.catalog import park_by_id
from app.community.models import DailyNatureBrief, EcologySnapshot


def build_daily_brief(snapshot: EcologySnapshot) -> DailyNatureBrief:
    park = park_by_id(snapshot.park_id)
    if park is None:
        raise KeyError(snapshot.park_id)
    ranked = sorted(snapshot.sound_type_counts.items(), key=lambda item: item[1], reverse=True)
    main_type = ranked[0][0] if ranked else None
    if snapshot.data_sufficiency == "low":
        return DailyNatureBrief(
            park_id=snapshot.park_id,
            park_name=park["name"],
            headline=f"{park['name']}正在等待更多声音",
            summary="近期有效社区录音还不足以形成稳定趋势。完成一次规范观察，就能帮助补齐公园声景。",
            facts=[
                f"近期有效观察 {snapshot.valid_post_count} 条",
                f"独立探员 {snapshot.independent_observer_count} 位",
                f"覆盖 {snapshot.observation_day_count} 个观察日",
            ],
            possible_explanations=["上传量较少不代表公园里没有动物。"],
            mission="选择清晨或傍晚，在公开步道上完成一次20秒倾听。",
            data_sufficiency="low",
        )
    trend_text = {
        "higher": "社区声音记录比上一周期更多",
        "similar": "社区声音记录与上一周期接近",
        "lower": "社区声音记录比上一周期更少",
        "insufficient": "还需要更多连续观察",
    }[snapshot.activity_trend]
    headline = f"{park['name']}近期{main_type or '自然声音'}值得继续倾听"
    facts = [
        f"近期有效观察 {snapshot.valid_post_count} 条",
        f"来自 {snapshot.independent_observer_count} 位独立探员",
        f"覆盖 {snapshot.observation_day_count} 个观察日",
        trend_text,
    ]
    if main_type:
        facts.append(f"出现最多的声音类型是{main_type}（{snapshot.sound_type_counts[main_type]}条）")
    explanations = [
        "声音活动会受到时段、天气、季节和参与人数影响。",
        "记录变多或变少也可能来自参与人数变化，并不直接代表动物数量变化。",
    ]
    return DailyNatureBrief(
        park_id=snapshot.park_id,
        park_name=park["name"],
        headline=headline,
        summary="社区真实原声和现场观察显示了近期值得继续倾听的方向。",
        facts=facts,
        possible_explanations=explanations,
        mission="比较树冠、灌木或水边的声音有什么不同，并记录一个现场特点。",
        data_sufficiency=snapshot.data_sufficiency,
    )
