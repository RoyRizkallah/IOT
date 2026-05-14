"""MQTT topic conventions.

The whole system is built around these channels:

    home/sensors/<type>      ← raw readings from the sensors      (Pub: sensors)
    home/events              ← security events derived from those (Pub: agent)
    home/agent/state         ← latest aggregated SecurityState    (Pub: agent)
    home/agent/decision      ← AgentDecision records              (Pub: agent)
    home/agent/chat/out      ← agent chat replies                 (Pub: agent)
    home/agent/replay        ← bulk dump on request (history)     (Pub: agent)
    home/control/arm         ← arm/disarm commands                (Pub: app)
    home/control/siren       ← siren trigger / stop               (Pub: agent / app)
    home/control/chat/in     ← chat messages to the agent         (Pub: app)
    home/control/replay      ← request a history dump             (Pub: app)

Every payload is JSON. Schemas are the Pydantic models in `sentry.models`.
"""

from __future__ import annotations

from ..models import SensorType

# ─── Roots ────────────────────────────────────────────────────────────────────

SENSOR_PREFIX = "home/sensors"
EVENTS_TOPIC = "home/events"

STATE_TOPIC = "home/agent/state"
DECISION_TOPIC = "home/agent/decision"
CHAT_OUT_TOPIC = "home/agent/chat/out"
REPLAY_TOPIC = "home/agent/replay"

ARM_TOPIC = "home/control/arm"
SIREN_TOPIC = "home/control/siren"
CHAT_IN_TOPIC = "home/control/chat/in"
REPLAY_REQ_TOPIC = "home/control/replay"

# ─── Wildcards (for subscribers) ──────────────────────────────────────────────

SENSOR_WILDCARD = f"{SENSOR_PREFIX}/+"
CONTROL_WILDCARD = "home/control/+"


# ─── Helpers ──────────────────────────────────────────────────────────────────


def sensor_topic(t: SensorType) -> str:
    """`home/sensors/motion`, `home/sensors/door`, etc."""
    return f"{SENSOR_PREFIX}/{t.value}"


def parse_sensor_topic(topic: str) -> SensorType | None:
    """Inverse of `sensor_topic`. Returns None for non-sensor topics."""
    if not topic.startswith(SENSOR_PREFIX + "/"):
        return None
    suffix = topic[len(SENSOR_PREFIX) + 1 :]
    try:
        return SensorType(suffix)
    except ValueError:
        return None
