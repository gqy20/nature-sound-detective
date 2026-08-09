from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field, field_validator


AREA_NAMES = {
    "xihu": "西湖区",
    "shangcheng": "上城区",
    "gongshu": "拱墅区",
    "binjiang": "滨江区",
    "yuhang": "余杭区",
    "xiaoshan": "萧山区",
}


class PublicationMetadata(BaseModel):
    owner_id: str = Field(min_length=12, max_length=100)
    alias: str = Field(min_length=2, max_length=24)
    area_id: str = Field(pattern=r"^[a-z][a-z0-9_-]{1,30}$")
    area_name: str = Field(min_length=2, max_length=30)
    subject: str = Field(min_length=1, max_length=60)
    sound_type: str = Field(min_length=1, max_length=30)
    observed_at: datetime
    duration_ms: int = Field(ge=500, le=20_000)
    candidate_names: list[str] = Field(default_factory=list, max_length=3)
    field_observations: list[str] = Field(default_factory=list, max_length=8)
    model_snapshot: dict[str, Any] = Field(default_factory=dict)
    adult_confirmed: bool
    public_consent: bool
    review_consent: bool = False

    @field_validator("area_name")
    @classmethod
    def area_matches_known_id(cls, value: str, info):
        expected = AREA_NAMES.get(info.data.get("area_id"))
        if expected is not None and value != expected:
            raise ValueError("区域名称与区域编号不一致")
        return value


class AssistSubmission(BaseModel):
    responder_id: str = Field(min_length=12, max_length=100)
    choice: str = Field(min_length=1, max_length=60)
    also_heard: bool = False
    key_second: int | None = Field(default=None, ge=0, le=20)


class CommunityPost(BaseModel):
    id: str
    alias: str
    area_id: str
    area_name: str
    subject: str
    sound_type: str
    observed_at: datetime
    created_at: datetime
    audio_url: str
    duration_ms: int
    candidate_names: list[str]
    field_observations: list[str]
    status: str
    review_status: str
    response_count: int = 0
    response_summary: dict[str, int] = Field(default_factory=dict)
    owned_by_requester: bool = False


class AreaSummary(BaseModel):
    area_id: str
    area_name: str
    post_count: int
    waiting_count: int
    sound_types: list[str]


class PublicationResult(BaseModel):
    post: CommunityPost
    message: str = "你的发现已加入共听杭州"


def utc_now() -> datetime:
    return datetime.now(timezone.utc)
