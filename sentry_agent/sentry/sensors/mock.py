"""Mock sensor publisher.

Pretends to be the Pi: emits realistic-looking readings on
`home/sensors/<type>` topics until killed.

Three scenario modes:

  - "default"        — sleepy household, occasional motion, the odd door,
                       gentle temperature drift
  - "suspicious"     — periodic suspicious bursts (motion + sound + door
                       at the same time, after midnight)
  - "flapping"       — a door that keeps cycling (sensor noise demo)

Pick the scenario with `--scenario`. The default is good enough to drive
the agent through all three severity bands within a couple of minutes.
"""

from __future__ import annotations

import asyncio
import logging
import random
from datetime import UTC, datetime
from typing import Literal

from ..models import SensorReading, SensorType
from ..mqtt.bus import MqttBus
from ..mqtt.topics import sensor_topic

logger = logging.getLogger(__name__)

Scenario = Literal["default", "suspicious", "flapping"]


# ─────────────────────────────────────────────────────────────────────────────


class MockSensorPublisher:
    def __init__(
        self,
        *,
        bus: MqttBus,
        scenario: Scenario = "default",
        speed: float = 1.0,
    ):
        """speed: scale factor on tick interval (2.0 = twice as fast)."""
        self._bus = bus
        self._scenario = scenario
        self._speed = max(0.1, speed)

        self._stop = asyncio.Event()
        self._door_open = False
        self._temp_c = 21.5

    # ─────────────────────────────────────────────────────────────────

    async def run(self) -> None:
        bus_task = asyncio.create_task(self._bus.run(), name="mqtt-bus")
        loop_tasks = [
            asyncio.create_task(self._loop_temperature(), name="temperature"),
            asyncio.create_task(self._loop_sound(), name="sound"),
            asyncio.create_task(self._loop_motion(), name="motion"),
            asyncio.create_task(self._loop_door(), name="door"),
        ]
        if self._scenario == "suspicious":
            loop_tasks.append(
                asyncio.create_task(
                    self._scenario_suspicious(), name="scenario-suspicious"
                )
            )
        elif self._scenario == "flapping":
            loop_tasks.append(
                asyncio.create_task(self._scenario_flapping(), name="scenario-flapping")
            )

        try:
            await asyncio.wait(
                [bus_task, *loop_tasks], return_when=asyncio.FIRST_EXCEPTION
            )
        except asyncio.CancelledError:
            pass
        finally:
            self._stop.set()
            await self._bus.stop()
            for t in [bus_task, *loop_tasks]:
                t.cancel()
            await asyncio.gather(bus_task, *loop_tasks, return_exceptions=True)
            logger.info("Mock publisher shut down")

    async def stop(self) -> None:
        self._stop.set()
        await self._bus.stop()

    # ─────────────────────────────────────────────────────────────────
    # Per-sensor loops
    # ─────────────────────────────────────────────────────────────────

    async def _loop_temperature(self) -> None:
        """Slow random walk, ~21°C ± 3°C, publish every 5 sec."""
        while not self._stop.is_set():
            await self._sleep(5.0)
            self._temp_c += random.uniform(-0.3, 0.3)
            self._temp_c = max(15.0, min(28.0, self._temp_c))
            await self._publish(SensorType.temperature, self._temp_c, active=False)

    async def _loop_sound(self) -> None:
        """Background noise around 35–45dB, occasional spikes."""
        while not self._stop.is_set():
            await self._sleep(random.uniform(2.0, 4.0))
            if random.random() < 0.05:
                db = random.uniform(60, 78)
                logger.debug("Sound spike: %.1fdB", db)
                await self._publish(
                    SensorType.sound, db, active=db >= 60
                )
            else:
                db = random.uniform(32, 45)
                await self._publish(SensorType.sound, db, active=False)

    async def _loop_motion(self) -> None:
        """Sparse motion pulses; mostly idle."""
        while not self._stop.is_set():
            await self._sleep(random.uniform(8.0, 18.0))
            if random.random() < 0.4:
                await self._publish(SensorType.motion, 1.0, active=True)
                await self._sleep(random.uniform(2.0, 4.0))
                await self._publish(SensorType.motion, 0.0, active=False)

    async def _loop_door(self) -> None:
        """Rare door cycles (well-behaved in default mode)."""
        while not self._stop.is_set():
            await self._sleep(random.uniform(40.0, 90.0))
            await self._toggle_door()
            await self._sleep(random.uniform(3.0, 8.0))
            await self._toggle_door()

    # ─────────────────────────────────────────────────────────────────
    # Scenarios
    # ─────────────────────────────────────────────────────────────────

    async def _scenario_suspicious(self) -> None:
        """Every 30s, fire motion + sound + door simultaneously."""
        await self._sleep(8.0)
        while not self._stop.is_set():
            logger.info("⚠ scenario_suspicious: triggering corroborated event")
            await asyncio.gather(
                self._publish(SensorType.motion, 1.0, active=True),
                self._publish(SensorType.sound, random.uniform(65, 82), active=True),
                self._toggle_door(),
            )
            await self._sleep(2.5)
            await self._publish(SensorType.motion, 0.0, active=False)
            await self._sleep(30.0)

    async def _scenario_flapping(self) -> None:
        """Door cycles every ~6 seconds — looks like sensor noise."""
        await self._sleep(5.0)
        while not self._stop.is_set():
            await self._toggle_door()
            await self._sleep(random.uniform(4.0, 8.0))

    # ─────────────────────────────────────────────────────────────────
    # Helpers
    # ─────────────────────────────────────────────────────────────────

    async def _toggle_door(self) -> None:
        self._door_open = not self._door_open
        await self._publish(
            SensorType.door,
            1.0 if self._door_open else 0.0,
            active=self._door_open,
        )

    async def _publish(
        self,
        t: SensorType,
        value: float,
        *,
        active: bool,
    ) -> None:
        reading = SensorReading(
            type=t,
            value=round(float(value), 2),
            active=active,
            timestamp=datetime.now(UTC),
        )
        await self._bus.publish(sensor_topic(t), reading)

    async def _sleep(self, seconds: float) -> None:
        try:
            await asyncio.wait_for(self._stop.wait(), timeout=seconds / self._speed)
        except TimeoutError:
            return
