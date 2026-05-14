"""Tool registry — the small, audited surface the LLM is allowed to touch.

Each tool is:
  - declared with a JSON schema (sent to the model)
  - implemented as a plain async Python callable (executed by us)

The agent loop:
  1. Sends the tool schemas to the LLM along with the prompt
  2. The LLM emits a tool_call (name + args)
  3. We dispatch the call to the matching Python function
  4. We feed the result back to the LLM
  5. Loop until the LLM emits a final decision (no more tool calls)

Right now every tool is read-only or operates on the agent's local state
(no side effects on the home). Side-effecting tools like `trigger_siren`
will be wired to MQTT publishes in Phase 2a.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from .models import SecurityEvent, SecurityState, SensorType, ThreatLevel

# ─────────────────────────────────────────────────────────────────────────────
# Tool registry types
# ─────────────────────────────────────────────────────────────────────────────


ToolFn = Callable[..., Awaitable[dict[str, Any]]]


@dataclass(frozen=True)
class Tool:
    """One callable tool the LLM can invoke."""

    name: str
    description: str
    parameters: dict[str, Any]  # JSON schema
    fn: ToolFn

    def to_openai_schema(self) -> dict[str, Any]:
        """Render in OpenAI/Ollama tool-calling format."""
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            },
        }


# ─────────────────────────────────────────────────────────────────────────────
# Tool implementations
# ─────────────────────────────────────────────────────────────────────────────


class ToolContext:
    """Shared state passed to tool implementations. The agent loop owns it
    for the duration of one decision; tools read from it but don't mutate
    persistent state directly."""

    def __init__(
        self,
        *,
        current_state: SecurityState,
        recent_events: list[SecurityEvent],
    ):
        self.current_state = current_state
        self.recent_events = recent_events
        # Side-effects requested by the LLM during this decision:
        self.requested_siren = False
        self.requested_notify = False
        self.acknowledged_event_ids: list[str] = []
        self.muted_sensors: list[SensorType] = []


def build_tools(ctx: ToolContext) -> list[Tool]:
    """Construct the tool list bound to a single decision context.

    Closing over `ctx` keeps tool implementations tiny while still giving
    them access to the events / state they need.
    """

    async def query_recent_events(
        window_minutes: int = 60,
        sensor: str | None = None,
        min_severity: str | None = None,
    ) -> dict[str, Any]:
        cutoff = datetime.now(UTC) - timedelta(minutes=window_minutes)
        filtered = [e for e in ctx.recent_events if e.timestamp >= cutoff]

        if sensor:
            try:
                s_enum = SensorType(sensor)
                filtered = [e for e in filtered if e.sensor == s_enum]
            except ValueError:
                return {
                    "ok": False,
                    "error": f"Unknown sensor '{sensor}'. "
                    f"Valid: {[s.value for s in SensorType]}",
                }

        if min_severity:
            try:
                lvl = ThreatLevel(min_severity)
                lvl_idx = list(ThreatLevel).index(lvl)
                filtered = [
                    e
                    for e in filtered
                    if list(ThreatLevel).index(e.severity) >= lvl_idx
                ]
            except ValueError:
                return {
                    "ok": False,
                    "error": f"Unknown severity '{min_severity}'",
                }

        return {
            "ok": True,
            "count": len(filtered),
            "events": [
                {
                    "id": e.id,
                    "sensor": e.sensor.value,
                    "severity": e.severity.value,
                    "message": e.message,
                    "timestamp": e.timestamp.isoformat(),
                    "minutes_ago": int(
                        (datetime.now(UTC) - e.timestamp).total_seconds() / 60
                    ),
                }
                for e in filtered
            ],
        }

    async def query_sensor_state(sensor: str) -> dict[str, Any]:
        try:
            s_enum = SensorType(sensor)
        except ValueError:
            return {
                "ok": False,
                "error": f"Unknown sensor '{sensor}'. "
                f"Valid: {[s.value for s in SensorType]}",
            }
        for r in ctx.current_state.readings:
            if r.type == s_enum:
                return {
                    "ok": True,
                    "sensor": s_enum.value,
                    "value": r.value,
                    "unit": s_enum.unit,
                    "active": r.active,
                    "timestamp": r.timestamp.isoformat(),
                }
        return {"ok": False, "error": "Sensor not present in current state"}

    async def acknowledge_event(event_id: str, reason: str) -> dict[str, Any]:
        if not any(e.id == event_id for e in ctx.recent_events):
            return {"ok": False, "error": f"Unknown event_id '{event_id}'"}
        ctx.acknowledged_event_ids.append(event_id)
        return {"ok": True, "acknowledged": event_id, "reason": reason}

    async def trigger_siren(reason: str) -> dict[str, Any]:
        ctx.requested_siren = True
        return {
            "ok": True,
            "scheduled": True,
            "reason": reason,
            "note": "Siren trigger queued. Will fire after final decision is published.",
        }

    async def notify_user(message: str, urgency: str = "high") -> dict[str, Any]:
        if urgency not in ("low", "high", "critical"):
            return {"ok": False, "error": "urgency must be low | high | critical"}
        ctx.requested_notify = True
        return {"ok": True, "scheduled_notification": message, "urgency": urgency}

    async def mute_sensor(sensor: str, minutes: int = 60) -> dict[str, Any]:
        try:
            s_enum = SensorType(sensor)
        except ValueError:
            return {"ok": False, "error": f"Unknown sensor '{sensor}'"}
        ctx.muted_sensors.append(s_enum)
        return {"ok": True, "muted": s_enum.value, "minutes": minutes}

    return [
        Tool(
            name="query_recent_events",
            description=(
                "Look up sensor events from the recent past. Use this to check "
                "whether a current trigger is part of a pattern (e.g. multiple "
                "motion events in 10 minutes) or a one-off."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "window_minutes": {
                        "type": "integer",
                        "description": "How far back to look. Default 60.",
                        "default": 60,
                        "minimum": 1,
                        "maximum": 1440,
                    },
                    "sensor": {
                        "type": "string",
                        "enum": [s.value for s in SensorType],
                        "description": "Filter to one sensor type. Optional.",
                    },
                    "min_severity": {
                        "type": "string",
                        "enum": ["safe", "warning", "alert"],
                        "description": "Only return events at or above this severity.",
                    },
                },
                "required": [],
            },
            fn=query_recent_events,
        ),
        Tool(
            name="query_sensor_state",
            description=(
                "Read the current value of a single sensor. Useful when reasoning "
                "needs the latest reading (e.g. is the door currently open?)."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "sensor": {
                        "type": "string",
                        "enum": [s.value for s in SensorType],
                    }
                },
                "required": ["sensor"],
            },
            fn=query_sensor_state,
        ),
        Tool(
            name="acknowledge_event",
            description=(
                "Mark a past event as understood and benign. Use when you've "
                "concluded that a triggering event was harmless (e.g. expected "
                "entry by the homeowner)."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "event_id": {
                        "type": "string",
                        "description": "ID of the event from query_recent_events.",
                    },
                    "reason": {
                        "type": "string",
                        "description": "One-line rationale logged with the ack.",
                    },
                },
                "required": ["event_id", "reason"],
            },
            fn=acknowledge_event,
        ),
        Tool(
            name="trigger_siren",
            description=(
                "Queue the physical siren. Reserved for confirmed intrusions or "
                "Red-zone events. Do NOT call this for ambiguous Yellow events — "
                "use notify_user instead so the homeowner can confirm."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "Why you're escalating to a siren.",
                    }
                },
                "required": ["reason"],
            },
            fn=trigger_siren,
        ),
        Tool(
            name="notify_user",
            description=(
                "Send a push notification to the homeowner. Use for Yellow events "
                "that need human judgment (e.g. unexpected motion at 3am)."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "message": {
                        "type": "string",
                        "description": "The notification body shown to the user.",
                    },
                    "urgency": {
                        "type": "string",
                        "enum": ["low", "high", "critical"],
                        "default": "high",
                    },
                },
                "required": ["message"],
            },
            fn=notify_user,
        ),
        Tool(
            name="mute_sensor",
            description=(
                "Temporarily silence a sensor when its readings are clearly noise "
                "(e.g. a door sensor flapping in the wind)."
            ),
            parameters={
                "type": "object",
                "properties": {
                    "sensor": {
                        "type": "string",
                        "enum": [s.value for s in SensorType],
                    },
                    "minutes": {
                        "type": "integer",
                        "minimum": 5,
                        "maximum": 360,
                        "default": 60,
                    },
                },
                "required": ["sensor"],
            },
            fn=mute_sensor,
        ),
    ]


# ─────────────────────────────────────────────────────────────────────────────
# Convenience: dispatch
# ─────────────────────────────────────────────────────────────────────────────


async def dispatch(tools: list[Tool], name: str, args: dict[str, Any]) -> dict[str, Any]:
    """Find a tool by name and run it with `args`. Returns a dict the LLM
    can read back."""
    for t in tools:
        if t.name == name:
            try:
                return await t.fn(**args)
            except TypeError as e:
                return {"ok": False, "error": f"Bad arguments to {name}: {e}"}
    return {"ok": False, "error": f"Unknown tool '{name}'"}
