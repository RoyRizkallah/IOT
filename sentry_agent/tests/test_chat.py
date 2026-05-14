"""Chat service + replay path. Stubbed LLM, no MQTT."""

from __future__ import annotations

import asyncio
import json
import uuid
from datetime import UTC, datetime
from typing import Any

import pytest

from sentry.agent import DecisionEngine
from sentry.chat import ChatService, parse_incoming_chat
from sentry.llm.base import ChatResponse, ToolCall
from sentry.models import (
    AgentDecision,
    ChatMessage,
    SecurityState,
    SensorReading,
    SensorType,
    ThreatLevel,
    ToolCallRecord,
)
from sentry.mqtt.bus import _topic_matches
from sentry.mqtt.topics import (
    CHAT_IN_TOPIC,
    CHAT_OUT_TOPIC,
    REPLAY_REQ_TOPIC,
    REPLAY_TOPIC,
)
from sentry.orchestrator import Orchestrator

# ─────────────────────────────────────────────────────────────────────────────
# Fakes (same shape as test_orchestrator.py)
# ─────────────────────────────────────────────────────────────────────────────


class _FakeBus:
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

    async def deliver(self, topic: str, payload: dict):
        for pat, h in self._handlers:
            if _topic_matches(topic, pat):
                await h(topic, payload)


class _ScriptedLLM:
    """Returns one ChatResponse per call."""

    def __init__(self, responses: list[ChatResponse]):
        self._responses = list(responses)
        self.calls: list[Any] = []

    async def chat(self, messages, tools=None, *, temperature=0.4, max_tokens=600):
        self.calls.append(messages)
        if not self._responses:
            return ChatResponse(content='{"reply":"(out of scripted responses)"}')
        return self._responses.pop(0)

    async def aclose(self):
        pass


class _NoopEngine:
    async def decide(self, req):
        raise AssertionError("engine should not run in chat tests")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def _state(threat: int = 1) -> SecurityState:
    now = datetime.now(UTC)
    return SecurityState(
        armed=False,
        threat_score=threat,
        readings=[
            SensorReading(type=SensorType.motion, value=0, active=False, timestamp=now),
            SensorReading(type=SensorType.sound, value=35, active=False, timestamp=now),
            SensorReading(type=SensorType.door, value=0, active=False, timestamp=now),
            SensorReading(type=SensorType.temperature, value=22, active=False, timestamp=now),
        ],
        last_update=now,
    )


# ─────────────────────────────────────────────────────────────────────────────
# parse_incoming_chat
# ─────────────────────────────────────────────────────────────────────────────


def test_parse_incoming_chat_minimal() -> None:
    m = parse_incoming_chat({"text": "hi"})
    assert m.role == "user"
    assert m.text == "hi"
    assert m.id.startswith("msg_")


def test_parse_incoming_chat_preserves_id() -> None:
    m = parse_incoming_chat({"id": "msg_xyz", "text": "hello"})
    assert m.id == "msg_xyz"


def test_parse_incoming_chat_rejects_empty() -> None:
    with pytest.raises(ValueError):
        parse_incoming_chat({"text": ""})


def test_parse_incoming_chat_truncates_long() -> None:
    big = "x" * 5000
    m = parse_incoming_chat({"text": big})
    assert len(m.text) <= 2000


# ─────────────────────────────────────────────────────────────────────────────
# ChatService
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_chat_returns_reply_from_json() -> None:
    llm = _ScriptedLLM(
        [ChatResponse(content='{"reply": "Everything looks calm right now."}')]
    )
    chat = ChatService(llm=llm)  # type: ignore[arg-type]

    user = ChatMessage(id="msg_1", role="user", text="how are things?")
    reply = await chat.reply(
        user_message=user,
        history=[],
        state=_state(),
        recent_events=[],
        recent_decisions=[],
    )
    assert reply.role == "agent"
    assert reply.in_reply_to == "msg_1"
    assert "calm" in reply.text.lower()


@pytest.mark.asyncio
async def test_chat_falls_back_when_json_is_unparseable() -> None:
    llm = _ScriptedLLM([ChatResponse(content="hmm I don't know")])
    chat = ChatService(llm=llm)  # type: ignore[arg-type]

    user = ChatMessage(id="msg_1", role="user", text="?")
    reply = await chat.reply(
        user_message=user,
        history=[],
        state=_state(),
        recent_events=[],
        recent_decisions=[],
    )
    # Either it picks up the prose, or falls back. Either way it's non-empty.
    assert reply.text


@pytest.mark.asyncio
async def test_chat_uses_tool_call_then_replies() -> None:
    """First turn: tool call. Second turn: final reply."""
    llm = _ScriptedLLM(
        [
            ChatResponse(
                content="",
                tool_calls=[
                    ToolCall(
                        id="c1",
                        name="query_sensor_state",
                        arguments={"sensor": "motion"},
                    )
                ],
            ),
            ChatResponse(
                content='{"reply": "Motion sensor reads 0 right now, all calm."}'
            ),
        ]
    )
    chat = ChatService(llm=llm)  # type: ignore[arg-type]

    user = ChatMessage(id="msg_2", role="user", text="is the motion sensor ok?")
    reply = await chat.reply(
        user_message=user,
        history=[],
        state=_state(),
        recent_events=[],
        recent_decisions=[],
    )
    assert "calm" in reply.text.lower()


# ─────────────────────────────────────────────────────────────────────────────
# Orchestrator chat + replay paths
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_orchestrator_chat_round_trip() -> None:
    bus = _FakeBus()
    llm = _ScriptedLLM([ChatResponse(content='{"reply": "yes, all quiet."}')])
    chat = ChatService(llm=llm)  # type: ignore[arg-type]
    orch = Orchestrator(
        bus=bus,
        engine=_NoopEngine(),  # type: ignore[arg-type]
        chat=chat,
    )
    orch._register_handlers()
    worker = asyncio.create_task(orch._chat_worker())

    try:
        await bus.deliver(
            CHAT_IN_TOPIC,
            {"id": "msg_in_1", "text": "everything ok?"},
        )

        for _ in range(60):
            await asyncio.sleep(0.02)
            if any(t == CHAT_OUT_TOPIC for t, _ in bus.published):
                break

        out = [(t, p) for t, p in bus.published if t == CHAT_OUT_TOPIC]
        assert out, "agent never replied"
        reply = out[0][1]
        assert getattr(reply, "in_reply_to", None) == "msg_in_1"
    finally:
        await orch.stop()
        worker.cancel()
        await asyncio.gather(worker, return_exceptions=True)


@pytest.mark.asyncio
async def test_orchestrator_replay_dumps_state_events_decisions() -> None:
    bus = _FakeBus()
    orch = Orchestrator(
        bus=bus,
        engine=_NoopEngine(),  # type: ignore[arg-type]
    )
    orch._register_handlers()

    # Seed some history
    orch._recent_decisions.appendleft(
        AgentDecision(
            id="dec_seed",
            severity=ThreatLevel.warning,
            summary="seeded",
            context="x",
            reasoning="y",
            tools_called=[
                ToolCallRecord(name="x", args_summary="{}", result_summary="{}")
            ],
            final_action="log",
            final_action_reason="seed",
        )
    )
    orch._chat_history.append(
        ChatMessage(id="msg_seed", role="user", text="hi", in_reply_to=None)
    )

    await bus.deliver(REPLAY_REQ_TOPIC, {})

    replays = [(t, p) for t, p in bus.published if t == REPLAY_TOPIC]
    assert len(replays) == 1
    bundle = replays[0][1]
    assert "state" in bundle
    assert "events" in bundle
    assert isinstance(bundle["decisions"], list)
    assert bundle["decisions"][0]["id"] == "dec_seed"
    assert bundle["chat"][0]["text"] == "hi"


# Silence unused-import warning
_ = DecisionEngine, json, uuid
