from app.evaluation import score_case, split_expected, summarize


def test_pipe_separated_sound_types_are_alternatives():
    case = {"expected_sound_types": "雨水|流水", "expected_species": ""}
    scored = score_case(case, {"primary_sound_type": "流水", "bird_species": []})
    assert split_expected(case["expected_sound_types"]) == ["雨水", "流水"]
    assert scored["sound_type_hit"] is True


def test_species_candidate_hit_uses_child_facing_chinese_name():
    case = {"expected_sound_types": "鸟类鸣叫", "expected_species": "乌鸫"}
    result = {"primary_sound_type": "鸟类鸣叫", "bird_species": [{"name_zh": "乌鸫"}]}
    scored = score_case(case, result)
    assert scored["sound_type_hit"] is True
    assert scored["species_hit"] is True


def test_summary_warns_when_weak_labels_are_present():
    report = summarize([
        {"label_status": "weak", "expected_sound_types": "风和树叶",
         "sound_type_evaluable": True, "sound_type_hit": True,
         "species_evaluable": False, "predicted_primary_sound_type": "风和树叶"}
    ])
    assert report["sound_type_hit_rate"] == 1.0
    assert "弱标签" in report["warning"]
    assert report["sound_confusions"] == {"风和树叶 -> 风和树叶": 1}
