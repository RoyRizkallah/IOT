"""Async MQTT bus.

A thin convenience layer over `aiomqtt`:

  - reconnects automatically when the broker drops
  - lets you register handlers with topic patterns (incl. `+` and `#`)
  - publishes JSON-serialisable Python values transparently

Typical use:

    bus = MqttBus(host="localhost", port=1883, client_id="sentry-orch")
    bus.on(SENSOR_WILDCARD)(handle_sensor_msg)
    bus.on(ARM_TOPIC)(handle_arm_msg)
    await bus.run()                # forever
    # later, from another task:
    await bus.publish(DECISION_TOPIC, decision.model_dump())

`bus.run()` blocks until cancelled. Use `asyncio.create_task(bus.run())`
to run it alongside other work.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

import aiomqtt
from pydantic import BaseModel

logger = logging.getLogger(__name__)


Handler = Callable[[str, dict[str, Any]], Awaitable[None]]
"""(topic, payload) → coroutine. Payload is already JSON-decoded."""


@dataclass
class _Sub:
    pattern: str
    handler: Handler


class MqttBus:
    def __init__(
        self,
        *,
        host: str = "localhost",
        port: int = 1883,
        client_id: str = "sentry-bus",
        keepalive: int = 30,
        reconnect_delay_s: float = 3.0,
    ):
        self.host = host
        self.port = port
        self.client_id = client_id
        self.keepalive = keepalive
        self.reconnect_delay_s = reconnect_delay_s

        self._subs: list[_Sub] = []
        self._client: aiomqtt.Client | None = None
        self._connected = asyncio.Event()
        self._stop = asyncio.Event()

    # ─── Subscriptions ───────────────────────────────────────────────

    def on(self, pattern: str) -> Callable[[Handler], Handler]:
        """Register a handler. Use as a decorator:

            @bus.on("home/sensors/+")
            async def handle(topic, payload): ...
        """

        def register(handler: Handler) -> Handler:
            self._subs.append(_Sub(pattern=pattern, handler=handler))
            logger.debug("Registered handler for %s", pattern)
            return handler

        return register

    # ─── Publish ─────────────────────────────────────────────────────

    async def publish(
        self,
        topic: str,
        payload: Any,
        *,
        qos: int = 0,
        retain: bool = False,
    ) -> None:
        """Publish a Python value as JSON. Pydantic models are unwrapped
        via `.model_dump(mode="json")`. Strings/bytes pass through."""
        await self._connected.wait()
        assert self._client is not None
        body = _encode(payload)
        await self._client.publish(topic, body, qos=qos, retain=retain)
        logger.debug("PUB %s (%d bytes)", topic, len(body))

    # ─── Run loop ────────────────────────────────────────────────────

    async def run(self) -> None:
        """Connect → subscribe → dispatch incoming messages forever.

        Reconnects on `aiomqtt.MqttError`. Returns only when `stop()` is
        called or the surrounding task is cancelled.
        """
        backoff = self.reconnect_delay_s
        while not self._stop.is_set():
            try:
                async with aiomqtt.Client(
                    hostname=self.host,
                    port=self.port,
                    identifier=self.client_id,
                    keepalive=self.keepalive,
                ) as client:
                    self._client = client
                    self._connected.set()
                    logger.info(
                        "MQTT connected: %s@%s:%d",
                        self.client_id,
                        self.host,
                        self.port,
                    )

                    for s in self._subs:
                        await client.subscribe(s.pattern)
                        logger.info("MQTT subscribed: %s", s.pattern)

                    async for msg in client.messages:
                        await self._dispatch(msg)
            except aiomqtt.MqttError as e:
                self._connected.clear()
                self._client = None
                if self._stop.is_set():
                    return
                logger.warning(
                    "MQTT connection error: %s. Reconnecting in %.1fs.",
                    e,
                    backoff,
                )
                try:
                    await asyncio.wait_for(self._stop.wait(), timeout=backoff)
                    return
                except TimeoutError:
                    pass

    async def stop(self) -> None:
        self._stop.set()
        self._connected.clear()

    # ─── Internals ───────────────────────────────────────────────────

    async def _dispatch(self, msg: aiomqtt.Message) -> None:
        topic = str(msg.topic)
        try:
            payload = _decode(msg.payload)
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            logger.warning("Drop unparseable msg on %s: %s", topic, e)
            return

        for s in self._subs:
            if _topic_matches(topic, s.pattern):
                try:
                    await s.handler(topic, payload)
                except Exception:
                    logger.exception("Handler for %s raised", s.pattern)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────


def _encode(payload: Any) -> bytes:
    """Serialise an arbitrary Python value to JSON bytes."""
    if isinstance(payload, bytes):
        return payload
    if isinstance(payload, str):
        return payload.encode("utf-8")
    if isinstance(payload, BaseModel):
        return payload.model_dump_json().encode("utf-8")
    return json.dumps(payload, default=str).encode("utf-8")


def _decode(raw: bytes | bytearray | str | None) -> dict[str, Any]:
    """JSON-decode incoming bytes. Empty payload → `{}`."""
    if raw is None or len(raw) == 0:
        return {}
    text = bytes(raw).decode("utf-8") if isinstance(raw, bytes | bytearray) else raw
    parsed = json.loads(text)
    if isinstance(parsed, dict):
        return parsed
    return {"_value": parsed}


def _topic_matches(topic: str, pattern: str) -> bool:
    """MQTT topic wildcards: `+` matches one segment, `#` matches the rest."""
    if pattern == topic:
        return True
    t_parts = topic.split("/")
    p_parts = pattern.split("/")
    for i, p in enumerate(p_parts):
        if p == "#":
            return True
        if i >= len(t_parts):
            return False
        if p == "+":
            continue
        if p != t_parts[i]:
            return False
    return len(t_parts) == len(p_parts)
