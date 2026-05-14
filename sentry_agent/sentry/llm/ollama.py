"""Ollama client.

Talks to a local Ollama server (default http://localhost:11434) using the
`/api/chat` endpoint with native tool calling (Ollama >= 0.4).

References:
  https://github.com/ollama/ollama/blob/main/docs/api.md#generate-a-chat-completion
"""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

import httpx

from .base import ChatMessage, ChatResponse, ToolCall

logger = logging.getLogger(__name__)


class OllamaClient:
    """Minimal Ollama HTTP client. One method: `chat`."""

    def __init__(
        self,
        *,
        model: str,
        base_url: str = "http://localhost:11434",
        request_timeout_s: float = 90.0,
    ):
        self.model = model
        self.base_url = base_url.rstrip("/")
        self._http = httpx.AsyncClient(
            timeout=httpx.Timeout(request_timeout_s, connect=10.0),
        )

    # ─── public API ──────────────────────────────────────────────────

    async def chat(
        self,
        messages: list[ChatMessage],
        tools: list[dict[str, Any]] | None = None,
        *,
        temperature: float = 0.2,
        max_tokens: int = 800,
    ) -> ChatResponse:
        body: dict[str, Any] = {
            "model": self.model,
            "messages": [m.to_provider_dict() for m in messages],
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens,
            },
        }
        if tools:
            body["tools"] = tools

        url = f"{self.base_url}/api/chat"
        logger.debug(
            "POST %s model=%s msgs=%d tools=%d",
            url,
            self.model,
            len(messages),
            len(tools or []),
        )

        try:
            resp = await self._http.post(url, json=body)
        except httpx.ConnectError as e:
            raise OllamaUnavailableError(
                f"Could not reach Ollama at {self.base_url}. "
                "Is the daemon running? Try `ollama serve` in a separate terminal."
            ) from e

        if resp.status_code != 200:
            raise OllamaError(
                f"Ollama returned {resp.status_code}: {resp.text[:500]}"
            )

        payload = resp.json()
        return _parse_response(payload)

    async def aclose(self) -> None:
        await self._http.aclose()

    # ─── helpers ─────────────────────────────────────────────────────

    async def ensure_model_available(self) -> None:
        """Best-effort check that the model is pulled. Logs a warning if not."""
        try:
            tags = await self._http.get(f"{self.base_url}/api/tags")
            tags.raise_for_status()
            installed = {m["name"] for m in tags.json().get("models", [])}
            # Ollama tags: "qwen2.5:7b-instruct" etc.
            wanted = self.model
            if wanted not in installed and not any(t.startswith(wanted) for t in installed):
                logger.warning(
                    "Model '%s' is not pulled locally. "
                    "Run: ollama pull %s",
                    wanted, wanted,
                )
        except Exception as e:
            logger.debug("Skipping model check: %s", e)


# ─────────────────────────────────────────────────────────────────────────────
# Parsing
# ─────────────────────────────────────────────────────────────────────────────


def _parse_response(payload: dict[str, Any]) -> ChatResponse:
    """Pull content + tool_calls out of an Ollama /api/chat response."""
    msg = payload.get("message", {})
    content = msg.get("content", "") or ""

    tool_calls: list[ToolCall] = []
    raw_calls = msg.get("tool_calls", []) or []
    for rc in raw_calls:
        fn = rc.get("function", {})
        name = fn.get("name", "")
        args = fn.get("arguments", {})
        # Some models emit arguments as a JSON string instead of an object —
        # tolerate both.
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                logger.warning("Tool args were a non-JSON string: %r", args)
                args = {}
        if not isinstance(args, dict):
            args = {}

        tool_calls.append(
            ToolCall(
                id=rc.get("id") or f"call_{uuid.uuid4().hex[:8]}",
                name=name,
                arguments=args,
            )
        )

    finish = "tool_calls" if tool_calls else "stop"
    return ChatResponse(
        content=content.strip(),
        tool_calls=tool_calls,
        finish_reason=finish,
        raw=payload,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Errors
# ─────────────────────────────────────────────────────────────────────────────


class OllamaError(RuntimeError):
    """Generic non-200 from Ollama."""


class OllamaUnavailableError(OllamaError):
    """Daemon not reachable — usually means `ollama serve` isn't running."""
