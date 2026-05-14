"""Orchestrator — the long-running service that ties everything together.

Subscribes to sensor + control topics, maintains live state and an event
window, runs the classifier + decision engine, and publishes decisions and
state back to MQTT.

Concurrency model:

  - The MQTT bus runs in its own task and dispatches incoming messages to
    handlers on this class.
  - Handlers are intentionally fast: they update state, classify, enqueue
    decisions, and return. They never wait for the LLM.
  - A single `_decision_worker` task pulls from the decision queue and
    invokes `engine.decide()` serially. This guarantees we never have two
    LLM calls in flight, and bounded queue size means a flood of events
    can't OOM the process.
  - A `_state_ticker` task republishes `home/agent/state` every few seconds
    so the UI stays alive even if no events arrive.
"""

from __future__ import annotations

import asyncio
import logging
from collections import deque
from datetime import UTC, datetime

from .agent import DecisionEngine, _short
from .chat import ChatService, parse_incoming_chat
from .event_classifier import (
    ClassifierContext,
    classify,
    threat_score_from_recent,
)
from .models import (
    AgentDecision,
    ChatMessage,
    DecisionRequest,
    SecurityEvent,
    SecurityState,
    SensorReading,
    SensorType,
    ThreatLevel,
)
from .mqtt.bus import MqttBus
from .mqtt.topics import (
    ARM_TOPIC,
    CHAT_IN_TOPIC,
    CHAT_OUT_TOPIC,
    DECISION_TOPIC,
    EVENTS_TOPIC,
    REPLAY_REQ_TOPIC,
    REPLAY_TOPIC,
    SENSOR_WILDCARD,
    SIREN_TOPIC,
    STATE_TOPIC,
    parse_sensor_topic,
)
from .storage import Storage

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────


class Orchestrator:
    def __init__(
        self,
        *,
        bus: MqttBus,
        engine: DecisionEngine,
        storage: Storage | None = None,
        chat: ChatService | None = None,
        history_window: int = 12,
        decision_history_size: int = 50,
        chat_history_size: int = 20,
        decision_queue_size: int = 10,
        chat_queue_size: int = 4,
        state_publish_interval_s: float = 5.0,
        decide_min_severity: ThreatLevel = ThreatLevel.warning,
        history_load_limit: int = 50,
    ):
        self._bus = bus
        self._engine = engine
        self._storage = storage
        self._chat = chat
        self._max_history = history_window
        self._state_publish_interval_s = state_publish_interval_s
        self._decide_min_severity = decide_min_severity
        self._history_load_limit = history_load_limit

        self._readings: dict[SensorType, SensorReading] = {}
        self._recent_events: deque[SecurityEvent] = deque(maxlen=history_window)
        self._recent_decisions: deque[AgentDecision] = deque(
            maxlen=decision_history_size
        )
        self._chat_history: deque[ChatMessage] = deque(maxlen=chat_history_size)
        self._armed: bool = False
        self._last_door_value: float | None = None

        self._decision_queue: asyncio.Queue[SecurityEvent] = asyncio.Queue(
            maxsize=decision_queue_size
        )
        self._chat_queue: asyncio.Queue[ChatMessage] = asyncio.Queue(
            maxsize=chat_queue_size
        )
        self._stop = asyncio.Event()

    # ─────────────────────────────────────────────────────────────────
    # Public lifecycle
    # ─────────────────────────────────────────────────────────────────

    async def run(self) -> None:
        """Block forever, running the bus + worker tasks together."""
        await self._hydrate_from_storage()
        self._register_handlers()

        tasks = [
            asyncio.create_task(self._bus.run(), name="mqtt-bus"),
            asyncio.create_task(self._decision_worker(), name="decision-worker"),
            asyncio.create_task(self._state_ticker(), name="state-ticker"),
        ]
        if self._chat is not None:
            tasks.append(
                asyncio.create_task(self._chat_worker(), name="chat-worker")
            )

        try:
            done, pending = await asyncio.wait(
                tasks, return_when=asyncio.FIRST_EXCEPTION
            )
            for t in done:
                if (exc := t.exception()) is not None:
                    logger.error("Task %s crashed: %s", t.get_name(), exc)
        except asyncio.CancelledError:
            pass
        finally:
            self._stop.set()
            await self._bus.stop()
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            logger.info("Orchestrator shut down")

    async def stop(self) -> None:
        self._stop.set()
        await self._bus.stop()

    # ─────────────────────────────────────────────────────────────────
    # Snapshot of the current state (handy for tests / debugging)
    # ─────────────────────────────────────────────────────────────────

    def current_state(self) -> SecurityState:
        readings = [
            self._readings[t]
            for t in SensorType
            if t in self._readings
        ]
        return SecurityState(
            armed=self._armed,
            threat_score=threat_score_from_recent(list(self._recent_events)),
            readings=readings,
            last_update=datetime.now(UTC),
        )

    # ─────────────────────────────────────────────────────────────────
    # Storage hydration
    # ─────────────────────────────────────────────────────────────────

    async def _hydrate_from_storage(self) -> None:
        """On startup, replay the last N rows from disk into the in-memory
        deques so the very first MQTT replay request returns history."""
        if self._storage is None:
            logger.info("No storage configured — running in-memory only")
            return

        limit = self._history_load_limit
        events = await self._storage.recent_events(limit=limit)
        decisions = await self._storage.recent_decisions(limit=limit)
        chat = await self._storage.recent_chat(limit=limit)
        state = await self._storage.latest_state()

        # Events / decisions are returned newest-first; deques are also
        # newest-first when we appendleft, so insert in chronological order.
        for ev in reversed(events):
            self._recent_events.appendleft(ev)
        for d in reversed(decisions):
            self._recent_decisions.appendleft(d)
        for m in chat:
            self._chat_history.append(m)

        if state is not None:
            self._armed = state.armed
            for r in state.readings:
                self._readings[r.type] = r

        logger.info(
            "Hydrated from disk: %d events, %d decisions, %d chat msgs%s",
            len(events),
            len(decisions),
            len(chat),
            ", state restored" if state else "",
        )

    # ─────────────────────────────────────────────────────────────────
    # Handler wiring
    # ─────────────────────────────────────────────────────────────────

    def _register_handlers(self) -> None:
        self._bus.on(SENSOR_WILDCARD)(self._on_sensor)
        self._bus.on(ARM_TOPIC)(self._on_arm)
        self._bus.on(REPLAY_REQ_TOPIC)(self._on_replay_request)
        if self._chat is not None:
            self._bus.on(CHAT_IN_TOPIC)(self._on_chat_in)

    # ─── Sensor message → optional event → maybe decision ──────────

    async def _on_sensor(self, topic: str, payload: dict) -> None:
        sensor_type = parse_sensor_topic(topic)
        if sensor_type is None:
            return

        try:
            reading = SensorReading.model_validate(
                {**payload, "type": sensor_type.value}
            )
        except Exception as e:
            logger.warning("Bad sensor payload on %s: %s", topic, e)
            return

        prev_door = (
            self._readings.get(SensorType.door).value
            if SensorType.door in self._readings
            else None
        )
        self._readings[sensor_type] = reading

        ctx = ClassifierContext(
            armed=self._armed,
            last_door_value=prev_door if sensor_type == SensorType.door else None,
        )
        event = classify(reading, ctx)

        if event is None:
            return  # boring reading, just updated state

        self._recent_events.appendleft(event)
        if self._storage is not None:
            await self._storage.record_event(event)
        await self._publish_event(event)

        # Only invoke the LLM for events at or above the configured floor.
        if _gte(event.severity, self._decide_min_severity):
            try:
                self._decision_queue.put_nowait(event)
            except asyncio.QueueFull:
                logger.warning(
                    "Decision queue full (n=%d), dropping %s",
                    self._decision_queue.qsize(),
                    event.id,
                )

    # ─── Arm/disarm command ─────────────────────────────────────────

    async def _on_arm(self, _topic: str, payload: dict) -> None:
        new_armed = bool(payload.get("armed", self._armed))
        if new_armed == self._armed:
            return
        self._armed = new_armed
        logger.info("ARM state → %s", self._armed)
        await self._publish_state()

    # ─── Chat: user → agent ─────────────────────────────────────────

    async def _on_chat_in(self, _topic: str, payload: dict) -> None:
        try:
            msg = parse_incoming_chat(payload)
        except ValueError as e:
            logger.warning("Bad chat payload: %s", e)
            return
        self._chat_history.append(msg)
        if self._storage is not None:
            await self._storage.record_chat(msg)
        try:
            self._chat_queue.put_nowait(msg)
        except asyncio.QueueFull:
            logger.warning("Chat queue full, dropping %s", msg.id)
            await self._publish_chat(
                ChatMessage(
                    id=f"msg_busy_{msg.id[:6]}",
                    role="agent",
                    text="I'm busy thinking about something. Try again in a few seconds.",
                    in_reply_to=msg.id,
                )
            )

    # ─── Replay: bulk state dump on request ────────────────────────

    async def _on_replay_request(self, _topic: str, _payload: dict) -> None:
        """The Flutter app pings this on (re)connect to backfill its UI."""
        bundle = {
            "state": self.current_state().model_dump(mode="json"),
            "events": [
                e.model_dump(mode="json") for e in list(self._recent_events)
            ],
            "decisions": [
                d.model_dump(mode="json") for d in list(self._recent_decisions)
            ],
            "chat": [
                m.model_dump(mode="json") for m in list(self._chat_history)
            ],
        }
        await self._bus.publish(REPLAY_TOPIC, bundle)
        logger.info(
            "Replayed: %d events, %d decisions, %d chat msgs",
            len(bundle["events"]),
            len(bundle["decisions"]),
            len(bundle["chat"]),
        )

    # ─────────────────────────────────────────────────────────────────
    # Background workers
    # ─────────────────────────────────────────────────────────────────

    async def _decision_worker(self) -> None:
        """Pull events off the queue, run the engine, publish results."""
        while not self._stop.is_set():
            try:
                event = await asyncio.wait_for(
                    self._decision_queue.get(), timeout=1.0
                )
            except TimeoutError:
                continue

            try:
                req = DecisionRequest(
                    triggering_event=event,
                    current_state=self.current_state(),
                    recent_events=list(self._recent_events),
                )
                logger.info(
                    "Deciding on %s (%s, sev=%s)",
                    event.id,
                    event.sensor.value,
                    event.severity.value,
                )
                decision = await self._engine.decide(req)
                self._recent_decisions.appendleft(decision)
                if self._storage is not None:
                    await self._storage.record_decision(decision)
                await self._publish_decision(decision)

                if decision.final_action == "trigger_siren":
                    await self._bus.publish(
                        SIREN_TOPIC,
                        {
                            "action": "trigger",
                            "decision_id": decision.id,
                            "reason": decision.final_action_reason,
                        },
                    )
            except Exception:
                logger.exception("Decision worker failed for event %s", event.id)

    async def _chat_worker(self) -> None:
        """One chat call at a time. Independent queue from decisions so
        the homeowner asking 'is everything ok?' doesn't get blocked
        behind a slow decision (and vice-versa)."""
        assert self._chat is not None
        while not self._stop.is_set():
            try:
                user_msg = await asyncio.wait_for(
                    self._chat_queue.get(), timeout=1.0
                )
            except TimeoutError:
                continue

            try:
                history_snapshot = list(self._chat_history)[:-1]  # exclude the just-added user msg
                logger.info("Chatting: %s", _short(user_msg.text))
                reply = await self._chat.reply(
                    user_message=user_msg,
                    history=history_snapshot,
                    state=self.current_state(),
                    recent_events=list(self._recent_events),
                    recent_decisions=list(self._recent_decisions),
                )
                self._chat_history.append(reply)
                if self._storage is not None:
                    await self._storage.record_chat(reply)
                await self._publish_chat(reply)
            except Exception:
                logger.exception("Chat worker failed for %s", user_msg.id)
                await self._publish_chat(
                    ChatMessage(
                        id=f"msg_err_{user_msg.id[:6]}",
                        role="agent",
                        text=(
                            "Hit an error while thinking about that — check the "
                            "agent logs. Try a simpler question?"
                        ),
                        in_reply_to=user_msg.id,
                    )
                )

    async def _state_ticker(self) -> None:
        """Heartbeat: republish state every N seconds so the UI stays warm."""
        while not self._stop.is_set():
            try:
                await asyncio.wait_for(
                    self._stop.wait(), timeout=self._state_publish_interval_s
                )
                return
            except TimeoutError:
                pass
            try:
                await self._publish_state()
            except Exception:
                logger.exception("state ticker failed")

    # ─────────────────────────────────────────────────────────────────
    # Publishers
    # ─────────────────────────────────────────────────────────────────

    async def _publish_state(self) -> None:
        state = self.current_state()
        if self._storage is not None:
            await self._storage.record_state(state)
        await self._bus.publish(STATE_TOPIC, state, retain=True)

    async def _publish_event(self, event: SecurityEvent) -> None:
        await self._bus.publish(EVENTS_TOPIC, event)

    async def _publish_decision(self, decision: AgentDecision) -> None:
        await self._bus.publish(DECISION_TOPIC, decision)

    async def _publish_chat(self, msg: ChatMessage) -> None:
        await self._bus.publish(CHAT_OUT_TOPIC, msg)


# ─── Helpers ─────────────────────────────────────────────────────────────────


_SEV_ORDER = {ThreatLevel.safe: 0, ThreatLevel.warning: 1, ThreatLevel.alert: 2}


def _gte(a: ThreatLevel, b: ThreatLevel) -> bool:
    return _SEV_ORDER[a] >= _SEV_ORDER[b]
