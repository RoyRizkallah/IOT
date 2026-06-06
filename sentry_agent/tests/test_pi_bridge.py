"""Raspberry Pi telemetry bridge.

The physical Pi publishes one combined message on `iot/pi/telemetry`. The
orchestrator must fan it out into the same classify -> event pipeline that
the per-sensor `home/sensors/*` publishers feed.
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest

from sentry.models import SensorType, ThreatLevel
from sentry.mqtt.bus import _topic_matches
from sentry.mqtt.topics import PI_TELEMETRY_TOPIC
from sentry.orchestrator import Orchestrator
from sentry.storage import Storage


class _FakeBus:
    def __init__(self) -> None:
        self.published: list[tuple[str, Any]] = []
        self._handlers: list[tuple[str, Any]] = []
        self._stop = asyncio.Event()

    def on(self, pattern: str):
        def reg(fn):
            self._handlers.append((pattern, fn))
            return fn

        return reg

    async def publish(self, topic, payload, *, qos: int = 0, retain: bool = False):
        self.published.append((topic, payload))

    async def run(self) -> None:
        await self._stop.wait()

    async def stop(self) -> None:
        self._stop.set()

    async def deliver(self, topic: str, payload: dict) -> None:
        for pat, h in self._handlers:
            if _topic_matches(topic, pat):
                await h(topic, payload)

    def has_handler(self, topic: str) -> bool:
        return any(_topic_matches(topic, pat) for pat, _ in self._handlers)


class _NoopEngine:
    async def decide(self, req):  # pragma: no cover - never invoked
        raise AssertionError("not used")


async def _make_orch(tmp_path: Path, **kwargs) -> tuple[Orchestrator, _FakeBus, Storage]:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    bus = _FakeBus()
    orch = Orchestrator(
        bus=bus,
        engine=_NoopEngine(),  # type: ignore[arg-type]
        storage=db,
        **kwargs,
    )
    await orch._hydrate_from_storage()
    orch._register_handlers()
    return orch, bus, db


def _telemetry(**overrides) -> dict:
    payload = {
        "temperature": 22.0,
        "humidity": 45,
        "motion": "Inactive",
        "noise": 120,
        "mode": "idle",
    }
    payload.update(overrides)
    return payload


@pytest.mark.asyncio
async def test_pi_motion_active_creates_event(tmp_path: Path) -> None:
    orch, bus, db = await _make_orch(tmp_path)
    try:
        await bus.deliver(PI_TELEMETRY_TOPIC, _telemetry(motion="Active"))

        rows = await db.recent_events()
        motion_events = [r for r in rows if r.sensor == SensorType.motion]
        assert len(motion_events) == 1
        # Live state reflects the active motion reading.
        assert orch._readings[SensorType.motion].active is True
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_pi_loud_noise_creates_alert_event(tmp_path: Path) -> None:
    orch, bus, db = await _make_orch(tmp_path)
    try:
        await bus.deliver(PI_TELEMETRY_TOPIC, _telemetry(noise=750))

        rows = await db.recent_events()
        sound_events = [r for r in rows if r.sensor == SensorType.sound]
        assert len(sound_events) == 1
        assert sound_events[0].severity in (ThreatLevel.warning, ThreatLevel.alert)
        assert orch._readings[SensorType.sound].active is True
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_pi_idle_telemetry_creates_no_events(tmp_path: Path) -> None:
    orch, bus, db = await _make_orch(tmp_path)
    try:
        await bus.deliver(PI_TELEMETRY_TOPIC, _telemetry())

        rows = await db.recent_events()
        assert rows == []
        # But state was still updated (temperature + idle readings present).
        assert SensorType.temperature in orch._readings
        assert orch._readings[SensorType.motion].active is False
        assert orch._readings[SensorType.sound].active is False
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_pi_noise_threshold_is_configurable(tmp_path: Path) -> None:
    # With a high threshold, 750 is no longer "loud".
    orch, bus, db = await _make_orch(tmp_path, pi_noise_threshold=1000.0)
    try:
        await bus.deliver(PI_TELEMETRY_TOPIC, _telemetry(noise=750))
        rows = await db.recent_events()
        assert [r for r in rows if r.sensor == SensorType.sound] == []
        assert orch._readings[SensorType.sound].active is False
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_pi_bridge_can_be_disabled(tmp_path: Path) -> None:
    orch, bus, db = await _make_orch(tmp_path, pi_bridge=False)
    try:
        assert bus.has_handler(PI_TELEMETRY_TOPIC) is False
        await bus.deliver(PI_TELEMETRY_TOPIC, _telemetry(motion="Active", noise=750))
        assert (await db.recent_events()) == []
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_pi_missing_fields_are_tolerated(tmp_path: Path) -> None:
    # A partial payload (e.g. DHT read failed -> temperature None) must not crash.
    orch, bus, db = await _make_orch(tmp_path)
    try:
        await bus.deliver(PI_TELEMETRY_TOPIC, {"motion": "Active"})
        rows = await db.recent_events()
        assert len(rows) == 1
        assert SensorType.temperature not in orch._readings
    finally:
        await db.close()
