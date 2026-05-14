"""Orchestrator integration tests with a fake bus and stubbed LLM.

These exercise the real wiring from sensor message → classifier → decision
queue → engine.decide() → publish — only the broker and the LLM are
swapped for in-process stubs.
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime
from typing import Any

import pytest

from sentry.agent import DecisionEngine
from sentry.llm.base import ChatResponse
from sentry.models import (
    AgentDecision,
    DecisionRequest,
    SensorType,
    ThreatLevel,
    ToolCallRecord,
)
from sentry.mqtt.bus import _topic_matches
from sentry.mqtt.topics import (
    ARM_TOPIC,
    DECISION_TOPIC,
    EVENTS_TOPIC,
    SIREN_TOPIC,
    STATE_TOPIC,
    sensor_topic,
)
from sentry.orchestrator import Orchestrator

# ─────────────────────────────────────────────────────────────────────────────
# Fakes
# ─────────────────────────────────────────────────────────────────────────────


class _FakeBus:
    """A drop-in MqttBus that records publishes and lets us inject incoming
    messages directly into registered handlers."""

    def __init__(self):
        self.published: list[tuple[str, Any]] = []
        self._handlers: list[tuple[str, Any]] = []
        self._stop = asyncio.Event()

    def on(self, pattern):
        def reg(fn):
            self._handlers.append((pattern, fn))
            return fn

        return reg

    async def publish(self, topic, payload, *, qos=0, retain=False):
        self.published.append((topic, payload))

    async def run(self):
        await self._stop.wait()

    async def stop(self):
        self._stop.set()

    # Test helper: inject a message
    async def deliver(self, topic: str, payload: dict):
        for pat, h in self._handlers:
            if _topic_matches(topic, pat):
                await h(topic, payload)


class _ScriptedDecisionEngine:
    """Returns a hard-coded AgentDecision regardless of input."""

    def __init__(self, *, final_action: str = "log"):
        self.calls: list[DecisionRequest] = []
        self._final_action = final_action

    async def decide(self, req: DecisionRequest) -> AgentDecision:
        self.calls.append(req)
        return AgentDecision(
            id=f"dec_{uuid.uuid4().hex[:8]}",
            severity=req.triggering_event.severity,
            summary="stub decision",
            context="test",
            reasoning="test",
            tools_called=[
                ToolCallRecord(name="noop", args_summary="{}", result_summary="{}")
            ],
            final_action=self._final_action,  # type: ignore[arg-type]
            final_action_reason="test",
        )


class _NeverDecideEngine:
    """Records calls but never finishes — used to assert the queue path."""

    async def decide(self, req: DecisionRequest) -> AgentDecision:
        await asyncio.sleep(60)
        raise AssertionError("should not finish in test")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


async def _drain(seconds: float = 0.05) -> None:
    """Yield enough times for queued tasks to run."""
    for _ in range(int(seconds / 0.005) + 1):
        await asyncio.sleep(0.005)


def _reading_payload(t: SensorType, value: float, *, active: bool, hour: int = 3) -> dict:
    return {
        "type": t.value,
        "value": value,
        "active": active,
        "timestamp": datetime(2026, 5, 9, hour, 0, 0, tzinfo=UTC).isoformat(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_safe_event_does_not_invoke_engine() -> None:
    """A boring daytime motion event becomes a 'safe' event — published to
    home/events but NOT fed to the LLM."""
    bus = _FakeBus()
    engine = _NeverDecideEngine()
    orch = Orchestrator(bus=bus, engine=engine)  # type: ignore[arg-type]
    orch._register_handlers()

    await bus.deliver(
        sensor_topic(SensorType.motion),
        _reading_payload(SensorType.motion, 1.0, active=True, hour=14),
    )

    topics = [t for t, _ in bus.published]
    assert EVENTS_TOPIC in topics
    assert DECISION_TOPIC not in topics


@pytest.mark.asyncio
async def test_warning_event_runs_engine_and_publishes_decision() -> None:
    bus = _FakeBus()
    engine = _ScriptedDecisionEngine(final_action="notify_user")
    orch = Orchestrator(bus=bus, engine=engine)  # type: ignore[arg-type]
    orch._register_handlers()
    worker = asyncio.create_task(orch._decision_worker())

    try:
        await bus.deliver(
            sensor_topic(SensorType.motion),
            _reading_payload(SensorType.motion, 1.0, active=True, hour=3),
        )

        for _ in range(50):
            await asyncio.sleep(0.02)
            if any(t == DECISION_TOPIC for t, _ in bus.published):
                break

        topics = [t for t, _ in bus.published]
        assert DECISION_TOPIC in topics
        assert SIREN_TOPIC not in topics
        assert len(engine.calls) == 1
        assert engine.calls[0].triggering_event.severity == ThreatLevel.warning
    finally:
        await orch.stop()
        worker.cancel()
        await asyncio.gather(worker, return_exceptions=True)


@pytest.mark.asyncio
async def test_trigger_siren_action_publishes_to_siren_topic() -> None:
    bus = _FakeBus()
    engine = _ScriptedDecisionEngine(final_action="trigger_siren")
    orch = Orchestrator(bus=bus, engine=engine)  # type: ignore[arg-type]
    orch._register_handlers()
    worker = asyncio.create_task(orch._decision_worker())

    try:
        await bus.deliver(
            sensor_topic(SensorType.sound),
            _reading_payload(SensorType.sound, 85.0, active=True, hour=3),
        )

        for _ in range(50):
            await asyncio.sleep(0.02)
            if any(t == SIREN_TOPIC for t, _ in bus.published):
                break

        topics = [t for t, _ in bus.published]
        assert SIREN_TOPIC in topics
        assert DECISION_TOPIC in topics
    finally:
        await orch.stop()
        worker.cancel()
        await asyncio.gather(worker, return_exceptions=True)


@pytest.mark.asyncio
async def test_arm_message_flips_state_and_publishes() -> None:
    bus = _FakeBus()
    engine = _NeverDecideEngine()
    orch = Orchestrator(bus=bus, engine=engine)  # type: ignore[arg-type]
    orch._register_handlers()

    assert orch._armed is False

    await bus.deliver(ARM_TOPIC, {"armed": True})
    assert orch._armed is True

    topics = [t for t, _ in bus.published]
    assert STATE_TOPIC in topics


@pytest.mark.asyncio
async def test_door_no_transition_does_nothing() -> None:
    bus = _FakeBus()
    engine = _NeverDecideEngine()
    orch = Orchestrator(bus=bus, engine=engine)  # type: ignore[arg-type]
    orch._register_handlers()

    # First door reading establishes state
    await bus.deliver(
        sensor_topic(SensorType.door),
        _reading_payload(SensorType.door, 1.0, active=True, hour=14),
    )
    bus.published.clear()

    # Same value again — no transition, no event
    await bus.deliver(
        sensor_topic(SensorType.door),
        _reading_payload(SensorType.door, 1.0, active=True, hour=14),
    )

    assert not any(t == EVENTS_TOPIC for t, _ in bus.published)


@pytest.mark.asyncio
async def test_decision_queue_capacity_drops_overflow() -> None:
    """If decisions back up, we drop new events rather than OOM."""
    bus = _FakeBus()
    engine = _NeverDecideEngine()
    orch = Orchestrator(
        bus=bus,
        engine=engine,  # type: ignore[arg-type]
        decision_queue_size=2,
    )
    orch._register_handlers()

    for _ in range(10):
        await bus.deliver(
            sensor_topic(SensorType.motion),
            _reading_payload(SensorType.motion, 1.0, active=True, hour=3),
        )

    assert orch._decision_queue.qsize() == 2


# Silence unused-import warnings on the engine class
_ = DecisionEngine, ChatResponse
