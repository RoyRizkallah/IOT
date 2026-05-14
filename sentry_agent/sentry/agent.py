"""Decision engine — the agent loop.

Given a `DecisionRequest`, the engine:

  1. renders the system + user prompts
  2. calls the LLM with the tool schemas
  3. dispatches any tool calls back into Python, feeds results back
  4. loops until the LLM returns a final assistant message with no tool calls
  5. parses + validates that final message as an `AgentDecision` (with one
     retry if the JSON is malformed)

The orchestrator (Phase 2a) wraps this with MQTT subscribe/publish.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Any

from .llm.base import ChatMessage, LLMClient
from .models import AgentDecision, DecisionRequest, ThreatLevel, ToolCallRecord
from .prompt import render, system_prompt
from .tools import ToolContext, build_tools, dispatch

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────


class DecisionEngine:
    """One engine instance, reused across many decisions."""

    def __init__(
        self,
        llm: LLMClient,
        *,
        max_tool_iterations: int = 5,
        max_format_retries: int = 1,
        temperature: float = 0.2,
        max_tokens: int = 800,
        hard_alert_threshold: int = 7,
    ):
        self.llm = llm
        self.max_tool_iterations = max_tool_iterations
        self.max_format_retries = max_format_retries
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.hard_alert_threshold = hard_alert_threshold

    async def decide(self, req: DecisionRequest) -> AgentDecision:
        """Run a single decision round and return the structured outcome."""

        # Hard escalation: skip LLM for unambiguous Red events.
        if req.triggering_event.severity == ThreatLevel.alert and (
            req.current_state.threat_score >= self.hard_alert_threshold
        ):
            return _hard_alert_decision(req)

        ctx = ToolContext(
            current_state=req.current_state,
            recent_events=req.recent_events,
        )
        tools = build_tools(ctx)
        tool_schemas = [t.to_openai_schema() for t in tools]

        messages: list[ChatMessage] = [
            ChatMessage(role="system", content=system_prompt()),
            ChatMessage(
                role="user",
                content=render(
                    "event_evaluation.j2",
                    event=req.triggering_event,
                    state=req.current_state,
                    recent_events=req.recent_events,
                    notes=req.notes,
                ),
            ),
        ]

        invoked_records: list[ToolCallRecord] = []

        # ── Tool-calling loop ─────────────────────────────────────────
        for iteration in range(self.max_tool_iterations):
            response = await self.llm.chat(
                messages,
                tools=tool_schemas,
                temperature=self.temperature,
                max_tokens=self.max_tokens,
            )

            if not response.tool_calls:
                # Model is ready to commit. Try to parse final JSON.
                logger.debug("LLM ready to commit on iteration %d", iteration)
                messages.append(
                    ChatMessage(role="assistant", content=response.content)
                )
                return await self._finalize(
                    messages=messages,
                    raw_content=response.content,
                    req=req,
                    invoked_records=invoked_records,
                    ctx=ctx,
                    tool_schemas=tool_schemas,
                )

            # Otherwise: dispatch each tool call, append results, loop.
            messages.append(
                ChatMessage(
                    role="assistant",
                    content=response.content,
                    tool_calls=response.tool_calls,
                )
            )

            for call in response.tool_calls:
                logger.info("LLM → tool: %s(%s)", call.name, call.arguments)
                result = await dispatch(tools, call.name, call.arguments)
                logger.info("tool → LLM: %s = %s", call.name, _short(result))

                invoked_records.append(
                    ToolCallRecord(
                        name=call.name,
                        args_summary=_short(call.arguments),
                        result_summary=_short(result),
                    )
                )

                messages.append(
                    ChatMessage(
                        role="tool",
                        content=json.dumps(result, default=str),
                        tool_call_id=call.id,
                        name=call.name,
                    )
                )

        # If we hit the iteration cap, force a final attempt with no tools.
        logger.warning(
            "Hit max_tool_iterations=%d, asking model to commit now.",
            self.max_tool_iterations,
        )
        messages.append(
            ChatMessage(
                role="user",
                content=(
                    "You've used enough tools. Emit your final decision JSON "
                    "now, exactly matching the schema in your system prompt."
                ),
            )
        )
        forced = await self.llm.chat(
            messages, tools=None, temperature=self.temperature, max_tokens=self.max_tokens
        )
        messages.append(ChatMessage(role="assistant", content=forced.content))
        return await self._finalize(
            messages=messages,
            raw_content=forced.content,
            req=req,
            invoked_records=invoked_records,
            ctx=ctx,
            tool_schemas=tool_schemas,
        )

    # ─── private ────────────────────────────────────────────────────

    async def _finalize(
        self,
        *,
        messages: list[ChatMessage],
        raw_content: str,
        req: DecisionRequest,
        invoked_records: list[ToolCallRecord],
        ctx: ToolContext,
        tool_schemas: list[dict[str, Any]],
    ) -> AgentDecision:
        """Parse the LLM's final JSON, retry once if malformed, then build
        the structured AgentDecision. Severity is anchored to the triggering
        event's severity (the LLM doesn't get to downgrade a Red event)."""

        for attempt in range(self.max_format_retries + 1):
            obj = _extract_json(raw_content)
            if obj is None:
                if attempt < self.max_format_retries:
                    messages.append(
                        ChatMessage(
                            role="user",
                            content=(
                                "Your last reply did not contain a valid JSON "
                                "object. Re-emit ONLY the final decision JSON "
                                "now, with no surrounding text."
                            ),
                        )
                    )
                    retry = await self.llm.chat(
                        messages,
                        tools=None,
                        temperature=self.temperature,
                        max_tokens=self.max_tokens,
                    )
                    raw_content = retry.content
                    messages.append(
                        ChatMessage(role="assistant", content=raw_content)
                    )
                    continue
                return _fallback_decision(req, invoked_records, raw_content)

            try:
                return AgentDecision(
                    id=f"dec_{uuid.uuid4().hex[:8]}",
                    severity=req.triggering_event.severity,
                    summary=obj.get("summary", "(no summary)")[:200],
                    context=obj.get("context", "")[:600],
                    reasoning=obj.get("reasoning", "")[:1200],
                    tools_called=invoked_records,
                    final_action=obj.get("final_action", "log"),
                    final_action_reason=obj.get(
                        "final_action_reason", "(no reason given)"
                    )[:300],
                )
            except Exception as e:  # pragma: no cover — pydantic error path
                logger.warning("Final JSON validation failed: %s", e)
                if attempt < self.max_format_retries:
                    messages.append(
                        ChatMessage(
                            role="user",
                            content=(
                                f"Your JSON had invalid fields: {e}. "
                                "Re-emit a corrected JSON object now."
                            ),
                        )
                    )
                    retry = await self.llm.chat(
                        messages,
                        tools=None,
                        temperature=self.temperature,
                        max_tokens=self.max_tokens,
                    )
                    raw_content = retry.content
                    messages.append(
                        ChatMessage(role="assistant", content=raw_content)
                    )
                    continue
                return _fallback_decision(req, invoked_records, raw_content)

        return _fallback_decision(req, invoked_records, raw_content)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


_FENCE_RE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL | re.IGNORECASE)
_OBJECT_RE = re.compile(r"\{.*\}", re.DOTALL)


def _extract_json(text: str) -> dict[str, Any] | None:
    """Best-effort JSON-from-text extraction.

    Tolerates: bare object, object inside ```json fence, object surrounded
    by prose. Returns None if nothing parses.
    """
    if not text:
        return None

    # Try a fenced code block first
    fence = _FENCE_RE.search(text)
    candidates: list[str] = []
    if fence:
        candidates.append(fence.group(1).strip())

    # Then the whole text trimmed
    candidates.append(text.strip())

    # Then the largest brace-delimited substring
    obj_match = _OBJECT_RE.search(text)
    if obj_match:
        candidates.append(obj_match.group(0))

    for c in candidates:
        try:
            v = json.loads(c)
            if isinstance(v, dict):
                return v
        except json.JSONDecodeError:
            continue
    return None


def _short(v: Any, limit: int = 240) -> str:
    """Compact one-line repr, capped at `limit` chars."""
    if isinstance(v, dict | list):
        try:
            s = json.dumps(v, default=str, separators=(",", ":"))
        except Exception:
            s = repr(v)
    else:
        s = str(v)
    s = s.replace("\n", " ").strip()
    return s if len(s) <= limit else s[: limit - 1] + "…"


def _hard_alert_decision(req: DecisionRequest) -> AgentDecision:
    """Synthesize an AgentDecision for a hard ALERT without invoking the LLM.

    Sirens fire fast; we don't make the user wait for the model to
    reason about a confirmed Red event.
    """
    return AgentDecision(
        id=f"dec_{uuid.uuid4().hex[:8]}",
        severity=ThreatLevel.alert,
        summary=f"Hard ALERT — {req.triggering_event.message}",
        context=(
            f"Triggering sensor: {req.triggering_event.sensor.value}. "
            f"Threat score {req.current_state.threat_score}/10."
        ),
        reasoning=(
            "Score is at or above the hard-alert threshold; the system "
            "escalates without LLM reasoning to avoid latency."
        ),
        tools_called=[
            ToolCallRecord(
                name="trigger_siren",
                args_summary='{"reason":"hard_alert_threshold"}',
                result_summary='{"ok":true,"scheduled":true}',
            )
        ],
        final_action="trigger_siren",
        final_action_reason=(
            "Score exceeds hard-alert threshold; siren fires immediately."
        ),
    )


def _fallback_decision(
    req: DecisionRequest,
    invoked_records: list[ToolCallRecord],
    raw_tail: str,
) -> AgentDecision:
    """Last-resort decision when the LLM never produced parseable output."""
    logger.error("Falling back. Raw tail: %r", raw_tail[:300])
    return AgentDecision(
        id=f"dec_{uuid.uuid4().hex[:8]}",
        severity=req.triggering_event.severity,
        summary="Agent could not produce a valid decision",
        context=(
            f"Triggering event: {req.triggering_event.message}. "
            f"Severity: {req.triggering_event.severity.value}."
        ),
        reasoning=(
            "The model failed to emit a schema-conforming decision after "
            "retries. Defaulting to notify_user so a human can adjudicate."
        ),
        tools_called=invoked_records,
        final_action="notify_user",
        final_action_reason="Model output was unparseable; deferring to human.",
    )
