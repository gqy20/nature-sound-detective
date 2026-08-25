from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Literal

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
    park_id: str | None = Field(default=None, pattern=r"^[a-z][a-z0-9-]{2,60}$")
    zone_id: str | None = Field(default=None, pattern=r"^[a-z][a-z0-9-]{2,60}$")
    site_id: str | None = Field(
        default=None,
        max_length=100,
        pattern=r"^[a-z][a-z0-9-]{2,60}:[a-z][a-z0-9-]{2,60}$",
    )
    sampling_mode: Literal["opportunistic", "guided_task", "fixed_monitoring"] = "opportunistic"
    sampling_effort: dict[str, Any] = Field(default_factory=dict)
    audio_quality: dict[str, Any] = Field(default_factory=dict)
    ecology_eligible: bool = True

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


class DeviceSessionRequest(BaseModel):
    device_id: str = Field(pattern=r"^device_[A-Za-z0-9_-]{12,120}$")


class DeviceSessionResponse(BaseModel):
    token: str
    expires_at: int


class ParentGuidanceRequest(BaseModel):
    candidate_name: str = Field(default="", max_length=60)
    category: str = Field(default="", max_length=40)
    confidence: float = Field(default=0, ge=0, le=1)
    weak_signal: bool = False
    observations: list[str] = Field(default_factory=list, max_length=12)
    behaviors: list[
        Literal[
            "recordedSound",
            "replayedAudio",
            "completedObservation",
            "comparedEvidence",
            "acceptedUncertainty",
            "retriedRecording",
            "observedSafely",
        ]
    ] = Field(min_length=1, max_length=8)


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
    park_id: str | None = None
    zone_id: str | None = None
    site_id: str | None = None
    sampling_mode: str = "opportunistic"
    sampling_effort: dict[str, Any] = Field(default_factory=dict)
    audio_quality: dict[str, Any] = Field(default_factory=dict)
    ecology_eligible: bool = True
    media_assets: list["CommunityMediaAsset"] = Field(default_factory=list)


class CommunityMediaAsset(BaseModel):
    id: str
    media_type: Literal["audio", "image", "video", "thumbnail"]
    source_type: Literal["original", "ai_generated", "composed"]
    url: str
    thumbnail_url: str | None = None
    provider: str | None = None
    model: str | None = None
    moderation_status: Literal["pending", "approved", "rejected"] = "approved"


class ParkSite(BaseModel):
    id: str
    park_id: str
    park_name: str
    zone_id: str
    zone_name: str
    area_id: str
    area_name: str
    public_centroid: dict[str, float]
    habitat_tags: list[str]


class ParkSummary(BaseModel):
    park_id: str
    park_name: str
    area_id: str
    area_name: str
    public_centroid: dict[str, float]
    habitat_tags: list[str]
    zone_count: int


class ZoneSoundscapeSummary(BaseModel):
    zone_id: str
    zone_name: str
    valid_post_count: int
    independent_observer_count: int
    sound_type_counts: dict[str, int]
    data_sufficiency: Literal["low", "medium", "high"]


class EcologySnapshot(BaseModel):
    park_id: str
    period_days: int
    valid_post_count: int
    independent_observer_count: int
    sound_type_counts: dict[str, int]
    reviewed_post_count: int
    data_sufficiency: Literal["low", "medium", "high"]
    observation_day_count: int = 0
    sampling_mode_counts: dict[str, int] = Field(default_factory=dict)
    previous_valid_post_count: int = 0
    activity_trend: Literal["insufficient", "higher", "similar", "lower"] = (
        "insufficient"
    )
    zone_summaries: list[ZoneSoundscapeSummary] = Field(default_factory=list)
    ecology_label: str = "社区声景观察趋势"
    disclaimer: str = "这是公众观察趋势，不替代专业生态监测。"


class DailyNatureBrief(BaseModel):
    park_id: str
    park_name: str
    headline: str
    summary: str
    facts: list[str]
    possible_explanations: list[str]
    mission: str
    data_sufficiency: Literal["low", "medium", "high"]
    disclaimer: str = "这是社区观察趋势，不代表动物数量或专业生态评估。"


class ExplorationRouteStop(BaseModel):
    site_id: str
    minutes: int
    mission: str


class ExplorationRoute(BaseModel):
    id: str
    park_id: str
    name: str
    duration_minutes: int
    distance_km: float
    age_min: int
    tags: list[str]
    stops: list[ExplorationRouteStop]
    disclaimer: str = "近期社区记录不保证一定遇见动物，请始终留在公开步道。"


CommunityPost.model_rebuild()


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
