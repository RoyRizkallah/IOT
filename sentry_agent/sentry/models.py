"""Domain models — the contract between sensors, the agent, and the Flutter app.

These mirror the Dart classes in `sentryagent_app/lib/data/models/security_state.dart`.
Field names are kept identical so JSON flows unchanged across the wire.
"""

from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field, field_serializer

# ─────────────────────────────────────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────────────────────────────────────


class SensorType(StrEnum):
    motion = "motion"
    sound = "sound"
    door = "door"
    temperature = "temperature"

    @property
    def display_name(self) -> str:
        return self.value.capitalize()

    @property
    def unit(self) -> str:
        return {
            SensorType.motion: "",
            SensorType.sound: "dB",
            SensorType.door: "",
            SensorType.temperature: "°C",
        }[self]


class ThreatLevel(StrEnum):
    safe = "safe"
    warning = "warning"
    alert = "alert"

    @classmethod
    def from_score(cls, score: int) -> ThreatLevel:
        if score >= 7:
            return cls.alert
        if score >= 4:
            return cls.warning
        return cls.safe

    @property
    def label(self) -> str:
        return self.value.upper()


# ─────────────────────────────────────────────────────────────────────────────
# Wire models
# ─────────────────────────────────────────────────────────────────────────────


def _utc_now() -> datetime:
    return datetime.now(UTC)


class SensorReading(BaseModel):
    type: SensorType
    value: float = Field(
        description="Numeric reading; dB for sound, °C for temp, 0/1 for motion/door"
    )
    active: bool
    timestamp: datetime = Field(default_factory=_utc_now)

    @field_serializer("timestamp")
    def _ser_ts(self, v: datetime) -> str:
        return v.astimezone(UTC).isoformat()


class SecurityEvent(BaseModel):
    """A discrete, log-worthy thing that happened."""

    id: str
    sensor: SensorType
    severity: ThreatLevel
    message: str = Field(description="Short human-readable summary of the event")
    timestamp: datetime = Field(default_factory=_utc_now)
    raw_value: float | None = None

    @field_serializer("timestamp")
    def _ser_ts(self, v: datetime) -> str:
        return v.astimezone(UTC).isoformat()


class SecurityState(BaseModel):
    """Snapshot of the home at a point in time. The agent uses this as
    immediate context — what is true RIGHT NOW."""

    armed: bool
    threat_score: int = Field(ge=0, le=10)
    readings: list[SensorReading]
    last_update: datetime = Field(default_factory=_utc_now)

    @property
    def level(self) -> ThreatLevel:
        return ThreatLevel.from_score(self.threat_score)

    @field_serializer("last_update")
    def _ser_ts(self, v: datetime) -> str:
        return v.astimezone(UTC).isoformat()


# ─────────────────────────────────────────────────────────────────────────────
# Agent decisions
# ─────────────────────────────────────────────────────────────────────────────


class ToolCallRecord(BaseModel):
    """One tool invocation by the agent. Logged so the user can audit reasoning."""

    name: str
    args_summary: str
    result_summary: str


class AgentDecision(BaseModel):
    """The structured output of the agent for one event.

    The Flutter Reasoning Log renders these directly. Field names match
    the Dart `AgentDecision` class exactly.
    """

    id: str
    timestamp: datetime = Field(default_factory=_utc_now)
    severity: ThreatLevel
    summary: str = Field(description="One-line headline")
    context: str = Field(description="What the agent saw")
    reasoning: str = Field(description="Why it decided what it did")
    tools_called: list[ToolCallRecord] = Field(default_factory=list)
    final_action: Literal[
        "ignore",
        "log",
        "notify_user",
        "request_confirmation",
        "trigger_siren",
        "auto_resolve",
    ]
    final_action_reason: str = Field(
        description="Human-readable phrasing of the action taken"
    )

    @field_serializer("timestamp")
    def _ser_ts(self, v: datetime) -> str:
        return v.astimezone(UTC).isoformat()


# ─────────────────────────────────────────────────────────────────────────────
# Decision request — what we feed the agent for one round
# ─────────────────────────────────────────────────────────────────────────────


class DecisionRequest(BaseModel):
    """Input bundle for one agent invocation. Everything the LLM needs to
    decide on a single triggering event lives in here."""

    triggering_event: SecurityEvent
    current_state: SecurityState
    recent_events: list[SecurityEvent] = Field(
        default_factory=list,
        description="Most-recent-first event log, capped by history_window_size",
    )
    notes: str | None = Field(
        default=None,
        description="Optional extra context the orchestrator wants the agent to know",
    )


# ─────────────────────────────────────────────────────────────────────────────
# Chat (over MQTT)
# ─────────────────────────────────────────────────────────────────────────────


class ChatMessage(BaseModel):
    """A single chat turn. Same shape as the Dart `ChatMessage`."""

    id: str
    role: Literal["user", "agent"]
    text: str
    timestamp: datetime = Field(default_factory=_utc_now)
    in_reply_to: str | None = Field(
        default=None,
        description="Set on agent replies — the id of the user message they answer.",
    )

    @field_serializer("timestamp")
    def _ser_ts(self, v: datetime) -> str:
        return v.astimezone(UTC).isoformat()
