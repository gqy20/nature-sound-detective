from __future__ import annotations

import json

import httpx
import pytest
from fastapi.testclient import TestClient

import api.index as cloud_api
import app.jobs as jobs_module
import app.main as main_module
import app.story_service as story_module
from app.jobs import JobStore
from app.cli import main as cli_main
from app.investigation import apply_structured_observations, build_investigation
from app.run_artifacts import write_run_package
from app.story_service import AnimalStoryService, _validate_story, story_candidates


RESULT = {
    "primary_sound_type": "鸟类鸣叫",
    "detections": [
        {
            "category_id": "bird",
            "name_zh": "鸟类鸣叫",
            "confidence": 0.8,
            "specific_species": {
                "name_zh": "白头鹎",
                "scientific_name": "Pycnonotus sinensis",
            },
        }
    ],
}
OBSERVATIONS = [
    {"dimension": "time", "value": "early_morning", "label": "清晨", "candidate_id": "Pycnonotus sinensis"},
    {"dimension": "habitat", "value": "tree_canopy", "label": "高处树冠", "candidate_id": "Pycnonotus sinensis"},
    {"dimension": "sound_pattern", "value": "repeated", "label": "重复鸣叫", "candidate_id": "Pycnonotus sinensis"},
]


def completed_investigation():
    initial = build_investigation(RESULT, "杭州", investigation_id="story-investigation")
    return apply_structured_observations(
        initial,
        candidate_id="Pycnonotus sinensis",
        selections={"time": ["early_morning"], "habitat": ["tree_canopy"], "sound_pattern": ["repeated"]},
        observed_at="2026-08-24T00:00:00+00:00",
    )


def test_story_candidates_are_limited_to_analysis_result():
    candidates = story_candidates(RESULT)
    assert candidates == [
        {
            "id": "Pycnonotus sinensis",
            "name_zh": "白头鹎",
            "scientific_name": "Pycnonotus sinensis",
            "category": "鸟类鸣叫",
            "candidate_status": "candidate",
        }
    ]
    assert story_candidates({"primary_sound_type": "风和树叶"}) == []


def test_template_story_is_available_without_api_key(monkeypatch):
    monkeypatch.setenv("STORY_MODE", "template")
    story = AnimalStoryService().create(
        result=RESULT,
        candidate_id="Pycnonotus sinensis",
        location="杭州",
        observations=OBSERVATIONS,
    )
    assert story["status"] == "completed"
    assert story["provider"] == "reviewed-template"
    assert "白头鹎" in story["story"]
    assert "不代表本次录音已经确认" in story["candidate_notice"]
    assert "认识候选动物" not in story["story"]


def test_live_story_uses_structured_output_and_safety_validation(monkeypatch):
    monkeypatch.setenv("STORY_MODE", "live")
    monkeypatch.setenv("STORY_API_KEY", "test-key")
    monkeypatch.setenv("STORY_MODEL", "qwen3.7-flash")
    response_payload = {
        "choices": [
            {
                "message": {
                    "content": json.dumps(
                        {
                            "title": "白头鹎的树梢时光",
                            "story": (
                                "白头鹎喜欢在树木和灌木之间活动。清晨醒来后，它在高处树冠用重复鸣叫与附近的伙伴保持联系，"
                                "也会在枝叶间寻找适合的食物。到了天气明亮的时候，它可能换到另一片树冠继续活动。"
                                "声音能帮助我们认识白头鹎，但每次听见时仍要结合外形、位置和周围环境继续观察。"
                            ),
                            "observation_prompt": "下一次可以远远观察白头鹎候选声音是否来自树冠附近。",
                            "observations_used": ["清晨", "高处树冠", "重复鸣叫"],
                        },
                        ensure_ascii=False,
                    )
                }
            }
        ],
        "usage": {"prompt_tokens": 100, "completion_tokens": 120},
    }

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == "Bearer test-key"
        body = json.loads(request.content)
        assert body["model"] == "qwen3.7-flash"
        assert body["enable_thinking"] is False
        assert body["max_completion_tokens"] == 500
        return httpx.Response(200, json=response_payload)

    real_client = httpx.Client
    monkeypatch.setattr(
        story_module.httpx,
        "Client",
        lambda **_kwargs: real_client(transport=httpx.MockTransport(handler)),
    )
    story = AnimalStoryService().create(
        result=RESULT,
        candidate_id="Pycnonotus sinensis",
        location="杭州",
        observations=OBSERVATIONS,
    )
    assert story["provider"] == "qwen3.7-flash"
    assert story["usage"]["completion_tokens"] == 120
    assert story["prompt_version"] == "animal-story-v5"


def test_story_policy_rejects_markdown_in_visible_content():
    candidate = story_candidates(RESULT)[0]
    with pytest.raises(ValueError, match="Markdown"):
        _validate_story(
            {
                "title": "白头鹎的树冠线索",
                "story": (
                    "清晨，白头鹎候选者在**高处树冠**留下了重复鸣叫的线索。"
                    "声音在枝叶附近出现又消失，我们只在远处记下当时听见的节奏和方向。"
                    "这些线索还不足以确认答案，却让下一次观察有了更清楚的目标。"
                ),
                "observation_prompt": "下一次在远处记录白头鹎候选声音的方向。",
                "observations_used": ["清晨", "高处树冠", "重复鸣叫"],
            },
            candidate,
            OBSERVATIONS,
        )


def test_story_policy_requires_every_observation_inside_story_body():
    candidate = story_candidates(RESULT)[0]
    with pytest.raises(ValueError, match="正文"):
        _validate_story(
            {
                "title": "白头鹎留下的线索",
                "story": (
                    "白头鹎候选者在枝叶附近留下了一段声音。"
                    "我们没有追过去，只在远处记下当时听见的节奏和方向。"
                    "这些线索还不足以确认答案，却让下一次观察有了更清楚的目标。"
                ),
                "observation_prompt": "下一次在远处记录白头鹎候选声音的方向。",
                "observations_used": ["清晨", "高处树冠", "重复鸣叫"],
            },
            candidate,
            OBSERVATIONS,
        )


def test_story_policy_rejects_conflicting_observation_time():
    candidate = story_candidates(RESULT)[0]
    daytime_observations = [
        {"dimension": "time", "value": "daytime", "label": "白天"},
        {"dimension": "habitat", "value": "tree_canopy", "label": "高处树冠"},
    ]
    with pytest.raises(ValueError, match="时间矛盾"):
        _validate_story(
            {
                "title": "白头鹎的白天线索",
                "story": (
                    "白天，白头鹎候选者在高处树冠留下了一段声音。"
                    "故事却又把这段相遇写成清晨，与现场记录并不相符。"
                    "我们只在远处记下当时听见的节奏和方向，等待下一次观察补上新的线索。"
                    "声音在周围环境里出现又消失，我们仍然把未知留给下一次相遇。"
                ),
                "observation_prompt": "下一次在远处记录白头鹎候选声音的方向。",
                "observations_used": ["白天", "高处树冠"],
            },
            candidate,
            daytime_observations,
        )


@pytest.mark.parametrize(
    "story",
    [
        "这段录音就是白头鹎。" * 15,
        "白头鹎会邀请孩子爬树靠近巢穴观察。" * 12,
        "白头鹎每年飞行3000公里。" * 15,
    ],
)
def test_story_policy_rejects_false_confirmation_danger_and_precise_numbers(story):
    candidate = story_candidates(RESULT)[0]
    with pytest.raises(ValueError):
        _validate_story(
            {
                "title": "白头鹎的故事",
                "story": story,
                "observation_prompt": "下一次远远观察白头鹎的活动。",
            },
            candidate,
        )


def test_story_policy_allows_explicit_safety_prohibition():
    candidate = story_candidates(RESULT)[0]
    validated = _validate_story(
        {
            "title": "白头鹎的安全观察故事",
            "story": (
                "白头鹎常在树木和灌木附近活动。清晨时，它会在枝叶之间移动，也可能用声音与附近的同伴联系。"
                "认识白头鹎候选时，可以留意它活动的位置和声音节奏，但不要追逐、捕捉或触摸动物。"
                "每一次记录都只是新的观察线索，还需要继续比较声音与外形。"
            ),
            "observation_prompt": "下一次可以远远观察白头鹎候选声音来自什么高度，请勿靠近巢穴。",
        },
        candidate,
    )
    assert "白头鹎" in validated["story"]


def test_story_policy_allows_observing_animal_hunting_behavior():
    candidate = story_candidates(RESULT)[0]
    validated = _validate_story(
        {
            "title": "白头鹎寻找食物的故事",
            "story": (
                "白头鹎会在树木和灌木间活动，也会寻找果实或小型昆虫。"
                "清晨时，它可能在枝叶之间移动，并用声音与附近的同伴保持联系。"
                "孩子可以从远处留意它活动的位置，不需要改变动物原本的生活。" * 2
            ),
            "observation_prompt": "请远远观察白头鹎如何捕捉小型昆虫，不要追逐或触摸它。",
        },
        candidate,
    )
    assert "捕捉" in validated["observation_prompt"]


@pytest.mark.parametrize("claim", ["它是湿地生态健康指标。", "这种动物不挖洞。", "它从不离开树冠。"])
def test_story_policy_rejects_unverified_absolute_claims(claim):
    candidate = story_candidates(RESULT)[0]
    with pytest.raises(ValueError, match="高风险或绝对"):
        _validate_story(
            {
                "title": "白头鹎的动物故事",
                "story": ("白头鹎会在周围环境中活动，也会通过声音与同伴联系。" * 5) + claim,
                "observation_prompt": "下一次可以远远观察白头鹎候选声音的节奏。",
            },
            candidate,
        )


def test_job_store_caches_story_by_candidate_and_type(tmp_path, monkeypatch):
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    calls = 0

    class FakeStoryService:
        def create(self, **kwargs):
            nonlocal calls
            calls += 1
            return {
                "status": "completed",
                "candidate": story_candidates(kwargs["result"])[0],
                "story_type": kwargs["story_type"],
                "title": "白头鹎的故事",
                "story": "测试故事",
                "observation_prompt": "远远观察",
            }

    monkeypatch.setattr(jobs_module, "AnimalStoryService", FakeStoryService)
    store = JobStore()
    store._jobs["story-job"] = {
        "id": "story-job",
        "status": "completed",
        "location": "杭州",
        "result": RESULT,
        "audio_path": str(tmp_path / "audio.wav"),
        "stories": {},
        "investigation": completed_investigation(),
        "creation": {"status": "idle"},
    }
    try:
        first = store.create_story("story-job", candidate_id="Pycnonotus sinensis")
        second = store.create_story("story-job", candidate_id="Pycnonotus sinensis")
        assert calls == 1
        assert first["cached"] is False
        assert second["cached"] is True
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)


def test_local_and_cloud_story_endpoints(monkeypatch, tmp_path):
    monkeypatch.setenv("STORY_MODE", "template")
    monkeypatch.setattr(jobs_module, "JOB_DIR", tmp_path)
    store = JobStore()
    store._jobs["story-api"] = {
        "id": "story-api",
        "status": "completed",
        "location": "杭州",
        "result": RESULT,
        "audio_path": str(tmp_path / "audio.wav"),
        "stories": {},
        "investigation": completed_investigation(),
        "creation": {"status": "idle"},
    }
    monkeypatch.setattr(main_module, "jobs", store)
    try:
        local = TestClient(main_module.app).post(
            "/api/jobs/story-api/stories",
            json={"candidate_id": "Pycnonotus sinensis", "story_type": "animal_life"},
        )
        assert local.status_code == 200
        assert local.json()["candidate"]["name_zh"] == "白头鹎"

        cloud = TestClient(cloud_api.app).post(
            "/api/stories",
            json={
                "result": RESULT,
                "candidate_id": "Pycnonotus sinensis",
                "story_type": "animal_life",
                "location": "杭州",
                "investigation": completed_investigation(),
            },
        )
        assert cloud.status_code == 200
        assert cloud.json()["candidate"]["name_zh"] == "白头鹎"
    finally:
        store._executor.shutdown(wait=True)
        store._creation_executor.shutdown(wait=True)


def test_web_contains_candidate_animal_story_contract():
    root = story_module.ROOT
    html = (root / "app/static/index.html").read_text(encoding="utf-8")
    javascript = (root / "app/static/app.js").read_text(encoding="utf-8")
    assert 'id="animal-story-block"' in html
    assert "animalStoryCandidates" in javascript
    assert "/stories" in javascript
    assert "candidate_notice" in javascript
    assert "先完成时间、环境、活动或声音特点" in javascript


def test_cli_generates_story_inside_run_package(tmp_path, monkeypatch):
    monkeypatch.setenv("STORY_MODE", "template")
    run_dir = write_run_package(
        tmp_path,
        run={
            "schema_version": 1,
            "run_id": "story-cli",
            "trace_id": "trace_story_cli",
            "created_at": "2026-08-24T00:00:00+00:00",
            "location": "杭州",
            "mode": "test",
        },
        result=RESULT,
        investigation=completed_investigation(),
    )
    assert cli_main(["story", str(run_dir), "--json"]) == 0
    outputs = list((run_dir / "stories").glob("*.json"))
    assert len(outputs) == 1
    assert json.loads(outputs[0].read_text(encoding="utf-8"))["candidate"]["name_zh"] == "白头鹎"
