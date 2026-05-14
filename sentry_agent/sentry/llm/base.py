"""Provider-neutral chat-with-tools surface.

We deliberately model after the OpenAI / Ollama tool-calling contract
because that's the lingua franca: anything we add later (Claude, vLLM,
LM Studio) will speak this dialect or be one wrapper away from it.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal, Protocol

Role = Literal["system", "user", "assistant", "tool"]


@dataclass
class ToolCall:
    """One tool invocation requested by the assistant."""

    id: str  # we may generate this if the provider doesn't
    name: str
    arguments: dict[str, Any]


@dataclass
class ChatMessage:
    """One turn in the conversation."""

    role: Role
    content: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    tool_call_id: str | None = None  # set when role == "tool"
    name: str | None = None  # tool name, for tool-result messages

    def to_provider_dict(self) -> dict[str, Any]:
        """Serialize in the OpenAI-shaped format Ollama also accepts."""
        d: dict[str, Any] = {"role": self.role, "content": self.content}
        if self.tool_calls:
            d["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": tc.name,
                        "arguments": tc.arguments,
                    },
                }
                for tc in self.tool_calls
            ]
        if self.tool_call_id is not None:
            d["tool_call_id"] = self.tool_call_id
        if self.name is not None:
            d["name"] = self.name
        return d


@dataclass
class ChatResponse:
    """Result of one chat call."""

    content: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    finish_reason: str = "stop"
    raw: dict[str, Any] = field(default_factory=dict)


class LLMClient(Protocol):
    """The single method we lean on: send messages + tools, get a response."""

    async def chat(
        self,
        messages: list[ChatMessage],
        tools: list[dict[str, Any]] | None = None,
        *,
        temperature: float = 0.2,
        max_tokens: int = 800,
    ) -> ChatResponse: ...

    async def aclose(self) -> None: ...
