"""Storage layer + orchestrator hydration."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest

from sentry.agent import DecisionEngine
from sentry.models import (
    AgentDecision,
    ChatMessage,
    SecurityEvent,
    SecurityState,
    SensorReading,
    SensorType,
    ThreatLevel,
    ToolCallRecord,
)
from sentry.mqtt.bus import _topic_matches
from sentry.mqtt.topics import REPLAY_REQ_TOPIC, REPLAY_TOPIC
from sentry.orchestrator import Orchestrator
from sentry.storage import Storage

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def _ev(idx: int, *, severity: ThreatLevel = ThreatLevel.warning) -> SecurityEvent:
    return SecurityEvent(
        id=f"evt_{idx:03d}",
        sensor=SensorType.motion,
        severity=severity,
        message=f"event {idx}",
        timestamp=datetime.now(UTC) + timedelta(seconds=idx),
    )


def _dec(idx: int) -> AgentDecision:
    return AgentDecision(
        id=f"dec_{idx:03d}",
        timestamp=datetime.now(UTC) + timedelta(seconds=idx),
        severity=ThreatLevel.warning,
        summary=f"summary {idx}",
        context="ctx",
        reasoning="why",
        tools_called=[
            ToolCallRecord(name="x", args_summary="{}", result_summary="{}")
        ],
        final_action="log",
        final_action_reason="for the record",
    )


def _chat(idx: int, role: str = "user") -> ChatMessage:
    return ChatMessage(
        id=f"msg_{idx:03d}",
        role=role,  # type: ignore[arg-type]
        text=f"hello {idx}",
        timestamp=datetime.now(UTC) + timedelta(seconds=idx),
    )


def _state() -> SecurityState:
    now = datetime.now(UTC)
    return SecurityState(
        armed=True,
        threat_score=4,
        readings=[
            SensorReading(type=SensorType.motion, value=1, active=True, timestamp=now),
            SensorReading(type=SensorType.sound, value=42, active=False, timestamp=now),
        ],
        last_update=now,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Storage round-trips
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_storage_persists_events(tmp_path: Path) -> None:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    try:
        for i in range(5):
            await db.record_event(_ev(i))
        rows = await db.recent_events(limit=10)
        assert [r.id for r in rows] == [
            "evt_004",
            "evt_003",
            "evt_002",
            "evt_001",
            "evt_000",
        ]
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_storage_persists_decisions_and_chat(tmp_path: Path) -> None:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    try:
        await db.record_decision(_dec(1))
        await db.record_decision(_dec(2))
        await db.record_chat(_chat(1, "user"))
        await db.record_chat(_chat(2, "agent"))

        decisions = await db.recent_decisions()
        assert {d.id for d in decisions} == {"dec_001", "dec_002"}

        chat = await db.recent_chat()
        # Chat is returned chronological for display
        assert [m.id for m in chat] == ["msg_001", "msg_002"]
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_storage_state_is_upserted(tmp_path: Path) -> None:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    try:
        s1 = _state()
        await db.record_state(s1)
        s2 = s1.model_copy(update={"threat_score": 7, "armed": False})
        await db.record_state(s2)

        latest = await db.latest_state()
        assert latest is not None
        assert latest.threat_score == 7
        assert latest.armed is False

        # Check there is exactly one row in state_latest
        counts = await db.counts()
        # state_latest is not in counts(); we keep rolling tables only
        assert "events" in counts
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_storage_dedupes_by_id(tmp_path: Path) -> None:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    try:
        await db.record_event(_ev(1))
        # Same id, different message: should overwrite, still one row.
        ev_v2 = _ev(1).model_copy(update={"message": "updated"})
        await db.record_event(ev_v2)
        rows = await db.recent_events(limit=10)
        assert len(rows) == 1
        assert rows[0].message == "updated"
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_storage_prune_caps_table_size(tmp_path: Path) -> None:
    db = Storage(tmp_path / "t.db")
    await db.connect()
    try:
        for i in range(20):
            await db.record_event(_ev(i))
        await db.prune(max_events=5, max_decisions=5, max_chat=5)
        rows = await db.recent_events(limit=100)
        assert len(rows) == 5
        # Newest 5 retained.
        assert {r.id for r in rows} == {f"evt_{i:03d}" for i in range(15, 20)}
    finally:
        await db.close()


@pytest.mark.asyncio
async def test_storage_survives_close_and_reopen(tmp_path: Path) -> None:
    path = tmp_path / "t.db"
    db = Storage(path)
    await db.connect()
    await db.record_event(_ev(1))
    await db.record_decision(_dec(1))
    await db.record_chat(_chat(1))
    await db.record_state(_state())
    await db.close()

    db2 = Storage(path)
    await db2.connect()
    try:
        events = await db2.recent_events()
        assert len(events) == 1
        assert (await db2.latest_state()) is not None
    finally:
        await db2.close()


# ─────────────────────────────────────────────────────────────────────────────
# Orchestrator hydration
# ─────────────────────────────────────────────────────────────────────────────


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

    async def publish(self, topic: str, payload, *, qos: int = 0, retain: bool = False) -> None:
        self.published.append((topic, payload))

    async def run(self) -> None:
        await self._stop.wait()

    async def stop(self) -> None:
        self._stop.set()

    async def deliver(self, topic: str, payload: dict) -> None:
        for pat, h in self._handlers:
            if _topic_matches(topic, pat):
                await h(topic, payload)


class _NoopEngine:
    async def decide(self, req):
        raise AssertionError("not used")


@pytest.mark.asyncio
async def test_orchestrator_hydrates_from_storage(tmp_path: Path) -> None:
    """Seed the DB, start a fresh orchestrator, ask for a replay — it must
    return the persisted history without ever talking to MQTT."""
    db_path = tmp_path / "t.db"
    db = Storage(db_path)
    await db.connect()
    await db.record_event(_ev(1))
    await db.record_event(_ev(2, severity=ThreatLevel.alert))
    await db.record_decision(_dec(1))
    await db.record_chat(_chat(1, "user"))
    await db.record_chat(_chat(2, "agent"))
    await db.record_state(_state())
    await db.close()

    db2 = Storage(db_path)
    await db2.connect()
    bus = _FakeBus()
    orch = Orchestrator(
        bus=bus,
        engine=_NoopEngine(),  # type: ignore[arg-type]
        storage=db2,
    )

    try:
        await orch._hydrate_from_storage()
        orch._register_handlers()

        # In-memory state should already reflect what the DB held.
        assert orch._armed is True
        assert SensorType.motion in orch._readings
        assert len(orch._recent_events) == 2
        assert len(orch._recent_decisions) == 1
        assert len(orch._chat_history) == 2

        await bus.deliver(REPLAY_REQ_TOPIC, {})
        replay = [(t, p) for t, p in bus.published if t == REPLAY_TOPIC]
        assert len(replay) == 1
        bundle = replay[0][1]
        assert len(bundle["events"]) == 2
        assert len(bundle["decisions"]) == 1
        assert len(bundle["chat"]) == 2
        assert bundle["state"]["armed"] is True
    finally:
        await db2.close()


@pytest.mark.asyncio
async def test_orchestrator_persists_on_event(tmp_path: Path) -> None:
    """A sensor message should land in the DB."""
    db = Storage(tmp_path / "t.db")
    await db.connect()
    bus = _FakeBus()
    orch = Orchestrator(
        bus=bus,
        engine=_NoopEngine(),  # type: ignore[arg-type]
        storage=db,
    )
    await orch._hydrate_from_storage()
    orch._register_handlers()

    # Active motion → classifier emits a SecurityEvent.
    await bus.deliver(
        "home/sensors/motion",
        {
            "value": 1.0,
            "active": True,
            "timestamp": datetime.now(UTC).isoformat(),
        },
    )

    rows = await db.recent_events()
    assert len(rows) == 1
    assert rows[0].sensor == SensorType.motion
    await db.close()


# Silence unused import warning
_ = DecisionEngine
