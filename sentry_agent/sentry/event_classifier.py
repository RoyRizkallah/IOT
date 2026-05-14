"""Event classifier — raw sensor readings → SecurityEvents.

This is the rule layer that sits between the dumb sensor stream and the
smart agent. Every `SensorReading` flows through `classify()`; most return
`None` (boring readings don't become events). The interesting ones become
`SecurityEvent`s that get logged, optionally fed to the LLM.

Severity is decided here using cheap, deterministic heuristics:

  - armed state (off-hours = more suspicious)
  - time of day (3am motion ≠ 7am motion)
  - sensor magnitude (60dB sound ≠ 90dB sound)

Anything ambiguous starts at `warning`. The LLM agent then decides whether
to escalate, notify, or de-escalate.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from .models import SecurityEvent, SensorReading, SensorType, ThreatLevel

# ─── Tunables ─────────────────────────────────────────────────────────────────

# Sound thresholds in dB
SOUND_NOISE_DB = 50.0  # below = ignore
SOUND_WARNING_DB = 60.0
SOUND_ALERT_DB = 80.0

# Hours considered "night" (local 24h). Inclusive start, exclusive end.
NIGHT_START_HOUR = 22
NIGHT_END_HOUR = 6

# Temperature thresholds in °C
TEMP_LOW_C = 5.0  # potential freeze / open window
TEMP_HIGH_C = 38.0  # potential fire


@dataclass
class ClassifierContext:
    """Inputs the classifier needs beyond the reading itself."""

    armed: bool
    last_door_value: float | None = None  # to detect state transitions


def classify(
    reading: SensorReading,
    ctx: ClassifierContext,
) -> SecurityEvent | None:
    """Decide whether this reading is event-worthy.

    Returns a `SecurityEvent` (with severity already set) or `None` to
    indicate "boring, skip".
    """
    match reading.type:
        case SensorType.motion:
            return _classify_motion(reading, ctx)
        case SensorType.sound:
            return _classify_sound(reading, ctx)
        case SensorType.door:
            return _classify_door(reading, ctx)
        case SensorType.temperature:
            return _classify_temperature(reading, ctx)


# ─────────────────────────────────────────────────────────────────────────────
# Per-sensor rules
# ─────────────────────────────────────────────────────────────────────────────


def _classify_motion(r: SensorReading, ctx: ClassifierContext) -> SecurityEvent | None:
    if not r.active or r.value < 1.0:
        return None

    night = _is_night(r)
    if ctx.armed and night:
        sev, msg = ThreatLevel.alert, "Motion detected while armed (night)"
    elif ctx.armed:
        sev, msg = ThreatLevel.warning, "Motion detected while armed"
    elif night:
        sev, msg = ThreatLevel.warning, "Motion detected at night"
    else:
        sev, msg = ThreatLevel.safe, "Motion detected"

    return _event(r, sev, msg)


def _classify_sound(r: SensorReading, ctx: ClassifierContext) -> SecurityEvent | None:
    if r.value < SOUND_NOISE_DB:
        return None

    if r.value >= SOUND_ALERT_DB:
        sev = ThreatLevel.alert
    elif r.value >= SOUND_WARNING_DB:
        sev = ThreatLevel.warning
    else:
        sev = ThreatLevel.safe

    if ctx.armed and _is_night(r) and sev != ThreatLevel.safe:
        # Night + armed + audible → bump one band
        sev = _bump(sev)

    return _event(r, sev, f"Sound spike at {r.value:.0f}dB")


def _classify_door(r: SensorReading, ctx: ClassifierContext) -> SecurityEvent | None:
    # Only emit on transitions (closed↔open). The orchestrator passes
    # `last_door_value` so we can tell.
    new = bool(r.value >= 0.5)
    if ctx.last_door_value is not None:
        old = bool(ctx.last_door_value >= 0.5)
        if old == new:
            return None  # no transition, skip

    msg_action = "opened" if new else "closed"

    if ctx.armed and _is_night(r):
        sev = ThreatLevel.alert
    elif ctx.armed or _is_night(r):
        sev = ThreatLevel.warning
    else:
        sev = ThreatLevel.safe

    return _event(r, sev, f"Door {msg_action}")


def _classify_temperature(r: SensorReading, _: ClassifierContext) -> SecurityEvent | None:
    if r.value <= TEMP_LOW_C:
        return _event(r, ThreatLevel.warning, f"Low temperature: {r.value:.1f}°C")
    if r.value >= TEMP_HIGH_C:
        return _event(r, ThreatLevel.alert, f"High temperature: {r.value:.1f}°C")
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def _event(r: SensorReading, sev: ThreatLevel, msg: str) -> SecurityEvent:
    return SecurityEvent(
        id=f"evt_{uuid.uuid4().hex[:8]}",
        sensor=r.type,
        severity=sev,
        message=msg,
        timestamp=r.timestamp,
        raw_value=r.value,
    )


def _is_night(r: SensorReading) -> bool:
    """True if the reading's local hour falls inside the night window."""
    hour = r.timestamp.hour
    if NIGHT_START_HOUR > NIGHT_END_HOUR:  # wraps midnight
        return hour >= NIGHT_START_HOUR or hour < NIGHT_END_HOUR
    return NIGHT_START_HOUR <= hour < NIGHT_END_HOUR


def _bump(sev: ThreatLevel) -> ThreatLevel:
    return {
        ThreatLevel.safe: ThreatLevel.warning,
        ThreatLevel.warning: ThreatLevel.alert,
        ThreatLevel.alert: ThreatLevel.alert,
    }[sev]


# ─────────────────────────────────────────────────────────────────────────────
# Aggregate threat score (0–10)
# ─────────────────────────────────────────────────────────────────────────────


def threat_score_from_recent(recent_events: list[SecurityEvent]) -> int:
    """Cheap rolling score from the last few events.

    The agent doesn't *need* this — it has the full event log — but the
    Flutter ThreatRing renders this and refreshing the score on every
    sensor tick keeps the UI feeling alive.
    """
    if not recent_events:
        return 0

    weights = {ThreatLevel.safe: 1, ThreatLevel.warning: 3, ThreatLevel.alert: 5}
    score = 0
    for e in recent_events[:6]:
        score += weights[e.severity]
    return min(10, score)
