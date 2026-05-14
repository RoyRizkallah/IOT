"""Event classifier rules — pure logic, no MQTT, no LLM."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from sentry.event_classifier import (
    ClassifierContext,
    classify,
    threat_score_from_recent,
)
from sentry.models import (
    SecurityEvent,
    SensorReading,
    SensorType,
    ThreatLevel,
)


def _at(hour: int) -> datetime:
    return datetime(2026, 5, 9, hour, 0, 0, tzinfo=UTC)


def _reading(
    t: SensorType,
    value: float,
    *,
    active: bool = False,
    hour: int = 12,
) -> SensorReading:
    return SensorReading(type=t, value=value, active=active, timestamp=_at(hour))


# ─────────────────────────────────────────────────────────────────────────────
# Motion
# ─────────────────────────────────────────────────────────────────────────────


def test_motion_inactive_returns_none() -> None:
    r = _reading(SensorType.motion, 0.0, active=False)
    assert classify(r, ClassifierContext(armed=False)) is None


def test_motion_during_day_unarmed_is_safe() -> None:
    r = _reading(SensorType.motion, 1.0, active=True, hour=14)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.safe


def test_motion_at_night_unarmed_is_warning() -> None:
    r = _reading(SensorType.motion, 1.0, active=True, hour=3)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.warning


def test_motion_armed_day_is_warning() -> None:
    r = _reading(SensorType.motion, 1.0, active=True, hour=14)
    ev = classify(r, ClassifierContext(armed=True))
    assert ev is not None
    assert ev.severity == ThreatLevel.warning


def test_motion_armed_night_is_alert() -> None:
    r = _reading(SensorType.motion, 1.0, active=True, hour=3)
    ev = classify(r, ClassifierContext(armed=True))
    assert ev is not None
    assert ev.severity == ThreatLevel.alert


# ─────────────────────────────────────────────────────────────────────────────
# Sound
# ─────────────────────────────────────────────────────────────────────────────


def test_sound_below_floor_is_skipped() -> None:
    r = _reading(SensorType.sound, 35.0, hour=14)
    assert classify(r, ClassifierContext(armed=False)) is None


def test_sound_warning_band() -> None:
    r = _reading(SensorType.sound, 65.0, hour=14)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.warning


def test_sound_alert_band() -> None:
    r = _reading(SensorType.sound, 85.0, hour=14)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.alert


def test_sound_armed_night_warning_bumps_to_alert() -> None:
    r = _reading(SensorType.sound, 65.0, hour=3)
    ev = classify(r, ClassifierContext(armed=True))
    assert ev is not None
    assert ev.severity == ThreatLevel.alert


# ─────────────────────────────────────────────────────────────────────────────
# Door — emits only on transitions
# ─────────────────────────────────────────────────────────────────────────────


def test_door_no_transition_returns_none() -> None:
    r = _reading(SensorType.door, 1.0, active=True, hour=14)
    assert classify(r, ClassifierContext(armed=False, last_door_value=1.0)) is None


def test_door_open_event_unarmed_day_is_safe() -> None:
    r = _reading(SensorType.door, 1.0, active=True, hour=14)
    ev = classify(r, ClassifierContext(armed=False, last_door_value=0.0))
    assert ev is not None
    assert ev.severity == ThreatLevel.safe
    assert "opened" in ev.message


def test_door_armed_night_is_alert() -> None:
    r = _reading(SensorType.door, 1.0, active=True, hour=3)
    ev = classify(r, ClassifierContext(armed=True, last_door_value=0.0))
    assert ev is not None
    assert ev.severity == ThreatLevel.alert


# ─────────────────────────────────────────────────────────────────────────────
# Temperature
# ─────────────────────────────────────────────────────────────────────────────


def test_temperature_normal_returns_none() -> None:
    r = _reading(SensorType.temperature, 22.0)
    assert classify(r, ClassifierContext(armed=False)) is None


def test_temperature_low_is_warning() -> None:
    r = _reading(SensorType.temperature, 3.0)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.warning


def test_temperature_high_is_alert() -> None:
    r = _reading(SensorType.temperature, 42.0)
    ev = classify(r, ClassifierContext(armed=False))
    assert ev is not None
    assert ev.severity == ThreatLevel.alert


# ─────────────────────────────────────────────────────────────────────────────
# threat_score_from_recent
# ─────────────────────────────────────────────────────────────────────────────


def test_threat_score_empty_is_zero() -> None:
    assert threat_score_from_recent([]) == 0


def test_threat_score_clamps_to_10() -> None:
    events = [
        SecurityEvent(
            id=f"e{i}",
            sensor=SensorType.motion,
            severity=ThreatLevel.alert,
            message="x",
        )
        for i in range(6)
    ]
    assert threat_score_from_recent(events) == 10


def test_threat_score_grows_with_severity() -> None:
    safe_events = [
        SecurityEvent(id=f"e{i}", sensor=SensorType.motion, severity=ThreatLevel.safe, message="")
        for i in range(3)
    ]
    warn_events = [
        SecurityEvent(
            id=f"e{i}",
            sensor=SensorType.motion,
            severity=ThreatLevel.warning,
            message="",
        )
        for i in range(3)
    ]
    assert threat_score_from_recent(warn_events) > threat_score_from_recent(safe_events)


# Pytest discovery
_ = pytest
