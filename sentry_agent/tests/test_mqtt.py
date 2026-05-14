"""MQTT plumbing — topic routing + payload encoding (no broker required)."""

from __future__ import annotations

import pytest

from sentry.models import SensorReading, SensorType
from sentry.mqtt.bus import _decode, _encode, _topic_matches
from sentry.mqtt.topics import (
    SENSOR_PREFIX,
    parse_sensor_topic,
    sensor_topic,
)

# ─── topic helpers ────────────────────────────────────────────────────────────


def test_sensor_topic_round_trip() -> None:
    for t in SensorType:
        assert parse_sensor_topic(sensor_topic(t)) == t


def test_parse_sensor_topic_rejects_other_prefixes() -> None:
    assert parse_sensor_topic("home/agent/state") is None
    assert parse_sensor_topic(SENSOR_PREFIX) is None
    assert parse_sensor_topic(f"{SENSOR_PREFIX}/zorp") is None


# ─── _topic_matches (mqtt wildcards) ──────────────────────────────────────────


@pytest.mark.parametrize(
    ("pattern", "topic", "expected"),
    [
        ("home/agent/state", "home/agent/state", True),
        ("home/agent/state", "home/agent/decision", False),
        ("home/sensors/+", "home/sensors/motion", True),
        ("home/sensors/+", "home/sensors/motion/extra", False),
        ("home/sensors/+", "home/agent/state", False),
        ("home/+/state", "home/agent/state", True),
        ("home/#", "home/agent/state/anything", True),
        ("home/#", "homer/agent/state", False),
        ("home/agent/#", "home/agent/decision", True),
        ("a/b", "a/b/c", False),
        ("a/b/c", "a/b", False),
    ],
)
def test_topic_matches(pattern: str, topic: str, expected: bool) -> None:
    assert _topic_matches(topic, pattern) is expected


# ─── encode / decode round trips ──────────────────────────────────────────────


def test_encode_dict_round_trip() -> None:
    assert _decode(_encode({"hello": "world"})) == {"hello": "world"}


def test_encode_str_passthrough() -> None:
    assert _encode("plain") == b"plain"


def test_encode_pydantic_model() -> None:
    r = SensorReading(type=SensorType.motion, value=1.0, active=True)
    body = _encode(r)
    decoded = _decode(body)
    assert decoded["type"] == "motion"
    assert decoded["value"] == 1.0


def test_decode_empty_returns_empty_dict() -> None:
    assert _decode(b"") == {}
    assert _decode(None) == {}


def test_decode_scalar_wraps() -> None:
    assert _decode(b"42") == {"_value": 42}
