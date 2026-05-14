"""Chat service.

Turns one user message into one agent reply, using the same tool surface
as the decision engine but with a different prompt and output contract.

Lives in its own module so the orchestrator can compose a chat handler
without entangling it with the per-event decision loop. Both share the
LLMClient instance.
"""

from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Any

from .agent import _extract_json, _short
from .llm.base import ChatMessage as LLMMessage
from .llm.base import LLMClient
from .models import (
    AgentDecision,
    ChatMessage,
    SecurityEvent,
    SecurityState,
)
from .prompt import render
from .tools import ToolContext, build_tools, dispatch

logger = logging.getLogger(__name__)


_FALLBACK_REPLY = (
    "Sorry — I couldn't put together a clean answer to that. Try rephrasing?"
)


class ChatService:
    """One service per orchestrator. Reuses the LLM and the tool registry."""

    def __init__(
        self,
        llm: LLMClient,
        *,
        max_tool_iterations: int = 4,
        max_format_retries: int = 1,
        temperature: float = 0.4,
        max_tokens: int = 600,
    ):
        self.llm = llm
        self.max_tool_iterations = max_tool_iterations
        self.max_format_retries = max_format_retries
        self.temperature = temperature
        self.max_tokens = max_tokens

    async def reply(
        self,
        *,
        user_message: ChatMessage,
        history: list[ChatMessage],
        state: SecurityState,
        recent_events: list[SecurityEvent],
        recent_decisions: list[AgentDecision],
    ) -> ChatMessage:
        """Run one chat turn and return the agent's reply."""

        ctx = ToolContext(current_state=state, recent_events=recent_events)
        tools = build_tools(ctx)
        tool_schemas = [t.to_openai_schema() for t in tools]

        messages: list[LLMMessage] = [
            LLMMessage(
                role="system",
                content=(
                    "You are SentryAgent's chat assistant. Be concise, "
                    "ground claims in tool results, and end every reply "
                    "with a JSON object {\"reply\": \"...\"}."
                ),
            ),
            LLMMessage(
                role="user",
                content=render(
                    "chat.j2",
                    state=state,
                    recent_events=recent_events,
                    recent_decisions=recent_decisions,
                    history=history,
                    user_message=user_message.text,
                ),
            ),
        ]

        # ── Tool-call loop (same shape as agent.py) ──────────────────
        for iteration in range(self.max_tool_iterations):
            response = await self.llm.chat(
                messages,
                tools=tool_schemas,
                temperature=self.temperature,
                max_tokens=self.max_tokens,
            )

            if not response.tool_calls:
                logger.debug("Chat ready to commit on iter %d", iteration)
                messages.append(LLMMessage(role="assistant", content=response.content))
                return self._finalize(user_message, response.content)

            messages.append(
                LLMMessage(
                    role="assistant",
                    content=response.content,
                    tool_calls=response.tool_calls,
                )
            )
            for call in response.tool_calls:
                logger.info("chat → tool: %s(%s)", call.name, call.arguments)
                result = await dispatch(tools, call.name, call.arguments)
                logger.info("tool → chat: %s = %s", call.name, _short(result))
                messages.append(
                    LLMMessage(
                        role="tool",
                        content=json.dumps(result, default=str),
                        tool_call_id=call.id,
                        name=call.name,
                    )
                )

        # Iteration cap: force a final answer.
        messages.append(
            LLMMessage(
                role="user",
                content=(
                    "Stop using tools and answer the homeowner now. "
                    'Emit only `{"reply": "..."}`.'
                ),
            )
        )
        forced = await self.llm.chat(
            messages,
            tools=None,
            temperature=self.temperature,
            max_tokens=self.max_tokens,
        )
        return self._finalize(user_message, forced.content)

    # ─── private ────────────────────────────────────────────────────

    def _finalize(self, user_message: ChatMessage, raw: str) -> ChatMessage:
        text = self._extract_reply(raw)
        return ChatMessage(
            id=f"msg_{uuid.uuid4().hex[:8]}",
            role="agent",
            text=text,
            in_reply_to=user_message.id,
        )

    def _extract_reply(self, raw: str) -> str:
        """Pull `reply` out of the model's JSON; fall back gracefully."""
        if not raw:
            return _FALLBACK_REPLY
        obj = _extract_json(raw)
        if obj and isinstance(obj.get("reply"), str):
            return obj["reply"].strip() or _FALLBACK_REPLY
        # Sometimes the model just answers in plain prose. If it's short
        # and sensible, use it directly. Strip any leading/trailing fences.
        cleaned = re.sub(r"^```(json)?|```$", "", raw, flags=re.IGNORECASE).strip()
        if cleaned and len(cleaned) < 800:
            return cleaned
        return _FALLBACK_REPLY


# Re-export so callers don't need to reach into agent.py directly.
_ = _extract_json, _short

__all__ = ["ChatService"]


# ─────────────────────────────────────────────────────────────────────────────
# Lightweight Pydantic-friendly helpers
# ─────────────────────────────────────────────────────────────────────────────


def parse_incoming_chat(payload: dict[str, Any]) -> ChatMessage:
    """Tolerant parsing of incoming chat from the Flutter app.

    The app must include `text`. Everything else is optional — we'll
    fill in id and timestamp if missing.
    """
    text = (payload.get("text") or "").strip()
    if not text:
        raise ValueError("Chat payload missing 'text'")
    return ChatMessage(
        id=payload.get("id") or f"msg_{uuid.uuid4().hex[:8]}",
        role="user",
        text=text[:2000],
        in_reply_to=None,
    )
