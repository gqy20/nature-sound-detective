from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator


FamilySessionStatus = Literal[
    "waiting_for_child",
    "pending_approval",
    "active",
    "ended",
    "expired",
]

FamilyRole = Literal["parent", "child"]

ALLOWED_EVENT_TYPES = {
    "captured_sound",
    "imported_sound",
    "replayed_audio",
    "completed_observation",
    "compared_evidence",
    "accepted_uncertainty",
    "retried_recording",
    "completed_safe_route_stop",
}

ALLOWED_COMMAND_TEMPLATES = {
    "compare_high_low_sound",
    "listen_again_before_guessing",
    "compare_sound_and_habitat",
    "keep_a_safe_distance",
    "allow_not_knowing",
}


class FamilySessionCreateResponse(BaseModel):
    session_id: str
    pair_code: str
    status: FamilySessionStatus
    pair_expires_at: datetime
    expires_at: datetime


class FamilySessionJoinRequest(BaseModel):
    pair_code: str = Field(pattern=r"^\d{6}$")


class FamilySessionView(BaseModel):
    session_id: str
    role: FamilyRole
    status: FamilySessionStatus
    child_joined: bool
    last_event_sequence: int = 0
    expires_at: datetime


class FamilyExplorationEventInput(BaseModel):
    event_id: str = Field(pattern=r"^evt_[A-Za-z0-9_-]{8,100}$")
    sequence: int = Field(ge=1, le=1_000_000)
    event_type: str
    occurred_at: datetime
    payload: dict[str, Any] = Field(default_factory=dict)

    @field_validator("event_type")
    @classmethod
    def validate_event_type(cls, value: str) -> str:
        if value not in ALLOWED_EVENT_TYPES:
            raise ValueError("不支持的探索事件类型")
        return value

    @field_validator("payload")
    @classmethod
    def validate_payload(cls, value: dict[str, Any]) -> dict[str, Any]:
        if len(json.dumps(value, ensure_ascii=False)) > 2000:
            raise ValueError("探索事件内容过大")
        return value


class FamilyExplorationEventBatch(BaseModel):
    events: list[FamilyExplorationEventInput] = Field(min_length=1, max_length=50)


class FamilyExplorationEvent(BaseModel):
    event_id: str
    sequence: int
    event_type: str
    occurred_at: datetime
    received_at: datetime
    payload: dict[str, Any]


class FamilyEventBatchResult(BaseModel):
    accepted: int
    last_sequence: int


class FamilyCommandCreate(BaseModel):
    template_id: str

    @field_validator("template_id")
    @classmethod
    def validate_template_id(cls, value: str) -> str:
        if value not in ALLOWED_COMMAND_TEMPLATES:
            raise ValueError("共同任务模板无效")
        return value


class FamilyCommand(BaseModel):
    command_id: str
    template_id: str
    sequence: int
    created_at: datetime
