"""Offline smoke tests — no Ollama required.

Run with: `pytest`

These verify the parts of the system that don't actually need an LLM:
fixtures, prompt rendering, JSON extraction, tool dispatch, and the
hard-alert short-circuit path.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from sentry.agent import (
    DecisionEngine,
    _extract_json,
    _hard_alert_decision,
)
from sentry.llm.base import ChatMessage, ChatResponse, ToolCall
from sentry.models import (
    AgentDecision,
    DecisionRequest,
    SecurityEvent,
    SecurityState,
    SensorReading,
    SensorType,
    ThreatLevel,
)
from sentry.prompt import render, system_prompt
from sentry.tools import ToolContext, build_tools, dispatch

FIXTURES = Path(__file__).parent / "fixtures"


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures parse cleanly
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("name", ["3am_back_door", "7am_kitchen_motion", "flapping_door"])
def test_fixture_parses_into_decision_request(name: str) -> None:
    with open(FIXTURES / f"{name}.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))
    assert req.triggering_event.id
    assert isinstance(req.triggering_event.sensor, SensorType)
    assert isinstance(req.triggering_event.severity, ThreatLevel)
    assert len(req.current_state.readings) == 4


# ─────────────────────────────────────────────────────────────────────────────
# Prompts render
# ─────────────────────────────────────────────────────────────────────────────


def test_system_prompt_renders() -> None:
    sp = system_prompt()
    assert "SentryAgent" in sp
    assert "trigger_siren" in sp
    assert "final_action" in sp


def test_event_evaluation_renders() -> None:
    with open(FIXTURES / "3am_back_door.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))
    text = render(
        "event_evaluation.j2",
        event=req.triggering_event,
        state=req.current_state,
        recent_events=req.recent_events,
        notes=req.notes,
    )
    assert "Motion detected near the back door" in text
    assert "## Recent event log" in text
    assert "**Armed:** yes" in text
    assert "## Operator notes" in text


# ─────────────────────────────────────────────────────────────────────────────
# JSON extraction tolerates a variety of model output shapes
# ─────────────────────────────────────────────────────────────────────────────


def test_extract_json_bare() -> None:
    obj = _extract_json('{"summary": "ok", "final_action": "log"}')
    assert obj == {"summary": "ok", "final_action": "log"}


def test_extract_json_fenced() -> None:
    obj = _extract_json(
        'Sure! Here is my decision:\n\n```json\n{"summary": "ok"}\n```\n'
    )
    assert obj == {"summary": "ok"}


def test_extract_json_with_prose() -> None:
    obj = _extract_json('Hmm, my final answer is {"summary": "ok"} done.')
    assert obj == {"summary": "ok"}


def test_extract_json_empty() -> None:
    assert _extract_json("") is None
    assert _extract_json("nothing to see") is None


# ─────────────────────────────────────────────────────────────────────────────
# Tools dispatch correctly
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_tools_query_recent_events_filters_by_sensor() -> None:
    with open(FIXTURES / "3am_back_door.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))
    ctx = ToolContext(current_state=req.current_state, recent_events=req.recent_events)
    tools = build_tools(ctx)

    result = await dispatch(tools, "query_recent_events", {"sensor": "motion"})
    assert result["ok"] is True
    assert all(e["sensor"] == "motion" for e in result["events"])


@pytest.mark.asyncio
async def test_tools_trigger_siren_records_request() -> None:
    with open(FIXTURES / "3am_back_door.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))
    ctx = ToolContext(current_state=req.current_state, recent_events=req.recent_events)
    tools = build_tools(ctx)
    result = await dispatch(tools, "trigger_siren", {"reason": "test"})
    assert result["ok"] is True
    assert ctx.requested_siren is True


@pytest.mark.asyncio
async def test_tools_unknown_returns_error() -> None:
    ctx = ToolContext(
        current_state=_minimal_state(),
        recent_events=[],
    )
    tools = build_tools(ctx)
    result = await dispatch(tools, "no_such_tool", {})
    assert result["ok"] is False
    assert "Unknown tool" in result["error"]


# ─────────────────────────────────────────────────────────────────────────────
# Hard-alert short-circuit doesn't call the LLM
# ─────────────────────────────────────────────────────────────────────────────


def test_hard_alert_short_circuits() -> None:
    state = _minimal_state(threat_score=9)
    req = DecisionRequest(
        triggering_event=SecurityEvent(
            id="evt_red",
            sensor=SensorType.door,
            severity=ThreatLevel.alert,
            message="Door forced",
        ),
        current_state=state,
        recent_events=[],
    )
    decision = _hard_alert_decision(req)
    assert decision.severity == ThreatLevel.alert
    assert decision.final_action == "trigger_siren"
    assert decision.tools_called[0].name == "trigger_siren"


# ─────────────────────────────────────────────────────────────────────────────
# Engine, with a stubbed LLM (no Ollama needed)
# ─────────────────────────────────────────────────────────────────────────────


class _StubLLM:
    """A scripted LLM that emits a fixed sequence of responses."""

    def __init__(self, scripted: list[ChatResponse]):
        self._scripted = list(scripted)

    async def chat(
        self,
        messages,
        tools=None,
        *,
        temperature=0.2,
        max_tokens=800,
    ) -> ChatResponse:
        return self._scripted.pop(0)

    async def aclose(self) -> None:
        pass


@pytest.mark.asyncio
async def test_engine_handles_tool_call_then_decision() -> None:
    """LLM calls one tool, then emits a final JSON decision. Engine should
    return a populated AgentDecision with one tool record."""

    scripted = [
        # Round 1: model wants to query recent events
        ChatResponse(
            content="",
            tool_calls=[
                ToolCall(
                    id="call_1",
                    name="query_recent_events",
                    arguments={"window_minutes": 60, "sensor": "motion"},
                )
            ],
            finish_reason="tool_calls",
        ),
        # Round 2: model commits with final JSON
        ChatResponse(
            content=json.dumps(
                {
                    "summary": "Motion is part of normal morning routine.",
                    "context": "Kitchen motion at 7:15am after bedroom motion.",
                    "reasoning": "Pattern matches the homeowner's wake-up routine.",
                    "final_action": "log",
                    "final_action_reason": "Benign morning activity.",
                }
            ),
            tool_calls=[],
        ),
    ]
    llm = _StubLLM(scripted)
    engine = DecisionEngine(llm=llm)

    with open(FIXTURES / "7am_kitchen_motion.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))

    decision = await engine.decide(req)
    assert isinstance(decision, AgentDecision)
    assert decision.final_action == "log"
    assert len(decision.tools_called) == 1
    assert decision.tools_called[0].name == "query_recent_events"


@pytest.mark.asyncio
async def test_engine_handles_malformed_json_with_retry() -> None:
    scripted = [
        # First final attempt: garbage
        ChatResponse(content="I think this is fine, sounds benign.", tool_calls=[]),
        # Retry: proper JSON
        ChatResponse(
            content='{"summary":"ok","context":"x","reasoning":"y","final_action":"log","final_action_reason":"z"}',
            tool_calls=[],
        ),
    ]
    llm = _StubLLM(scripted)
    engine = DecisionEngine(llm=llm, max_format_retries=1)

    with open(FIXTURES / "7am_kitchen_motion.json", encoding="utf-8") as f:
        req = DecisionRequest.model_validate(json.load(f))

    decision = await engine.decide(req)
    assert decision.final_action == "log"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def _minimal_state(*, threat_score: int = 3):
    now = datetime.now(UTC)
    return SecurityState(
        armed=True,
        threat_score=threat_score,
        readings=[
            SensorReading(type=SensorType.motion, value=0, active=False, timestamp=now),
            SensorReading(type=SensorType.sound, value=30, active=False, timestamp=now),
            SensorReading(type=SensorType.door, value=0, active=False, timestamp=now),
            SensorReading(type=SensorType.temperature, value=22, active=False, timestamp=now),
        ],
        last_update=now,
    )


# Silence the ChatMessage import warning when ChatMessage isn't used directly
_ = ChatMessage
