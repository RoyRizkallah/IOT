#!/usr/bin/env python3
"""
SentryAgent — Raspberry Pi sensor publisher.

Reads the physical sensors on a Raspberry Pi 3 and publishes their readings to
the MQTT broker every few seconds. Falls back to simulated values for any sensor
that isn't wired up, so the demo keeps running even if a sensor is missing.

WIRING (BCM pin numbers):
  - DHT11 temp/humidity .... GPIO 23
  - PIR motion sensor ...... GPIO 22
  - Sound sensor (digital) . GPIO 24
  - Buzzer (active) ........ GPIO 18  (pin 12)
  - Status LEDs (optional) . green 13, red 5, blue 19, white 26
  - Mode button (optional) . GPIO 6

RUN (must use the venv that has the libraries — see setup_pi.sh):
  /home/pi/iot-demo/venv/bin/python3 -u pi_sensor_publisher.py

Publishes JSON to MQTT topic `iot/pi/telemetry`. Listens on `iot/pi/control`
for {"buzzer": true} to fire the buzzer remotely.
"""
from __future__ import annotations

import json
import time

import paho.mqtt.client as mqtt

# ── Config ────────────────────────────────────────────────────────────────
MQTT_BROKER = "192.168.137.1"   # the PC running Mosquitto (hotspot/cable gateway)
MQTT_PORT = 1883                # plain TCP
TELEMETRY_TOPIC = "iot/pi/telemetry"
CONTROL_TOPIC = "iot/pi/control"
PUBLISH_INTERVAL = 1.0          # seconds between publishes
TEMP_BUZZER_THRESHOLD = 25.0    # °C — buzzer fires above this

# ── Pins (BCM) ──────────────────────────────────────────────────────────────
DHT_PIN_NUM = 23
PIR_MOTION_PIN = 22
SOUND_PIN = 24
BUZZER_PIN = 18
LED_GREEN, LED_RED, LED_BLUE, LED_WHITE = 13, 5, 19, 26
BUTTON_PIN = 6

# ── Hardware init (best-effort; each sensor degrades to simulation) ─────────
dht_device = None
_lgpio_handle = None
print("DHT11 will be read via subprocess (avoids blocking).")

motion = None
sound = None
buzzer_hw = None
led_green = led_red = led_blue = led_white = None
button = None
has_gpio = False
try:
    from gpiozero import LED, Button, Buzzer, MotionSensor, DigitalInputDevice

    motion = MotionSensor(PIR_MOTION_PIN, threshold=0.5, queue_len=1)
    sound = DigitalInputDevice(SOUND_PIN)
    buzzer_hw = Buzzer(BUZZER_PIN)
    led_green = LED(LED_GREEN)
    led_red = LED(LED_RED)
    led_blue = LED(LED_BLUE)
    led_white = LED(LED_WHITE)
    try:
        button = Button(BUTTON_PIN, pull_up=True)
    except Exception:  # noqa: BLE001
        button = None
    has_gpio = True
    print("GPIO devices initialized (motion, sound, buzzer, LEDs).")
except Exception as e:  # noqa: BLE001
    print(f"Could not initialize GPIO ({e}). Motion/sound/LEDs in simulation mode.")

# ── Simulation state (used only for unavailable sensors) ────────────────────
import random  # noqa: E402

_sim_motion = False
_last_motion_ts = int(time.time())


def read_temperature_humidity() -> tuple[float | None, float | None]:
    """Read DHT11 via kernel IIO driver (/sys/bus/iio/devices/iio:device0)."""
    try:
        with open("/sys/bus/iio/devices/iio:device0/in_temp_input") as f:
            t = float(f.read().strip()) / 1000.0
        with open("/sys/bus/iio/devices/iio:device0/in_humidityrelative_input") as f:
            h = float(f.read().strip()) / 1000.0
        return t, h
    except Exception:
        return None, None


def read_motion() -> bool:
    global _sim_motion
    if has_gpio and motion is not None:
        return bool(motion.motion_detected)
    _sim_motion = not _sim_motion if random.random() < 0.4 else _sim_motion
    return _sim_motion


def read_sound() -> float | None:
    """Digital sound sensor: 70.0 when the comparator detects noise, 40.0 when quiet."""
    if has_gpio and sound is not None:
        try:
            return 70.0 if sound.value else 40.0
        except Exception:  # noqa: BLE001
            return None
    return round(random.uniform(35, 75), 1)


def fire_buzzer(seconds: float = 2.0) -> None:
    if has_gpio and buzzer_hw is not None:
        buzzer_hw.on()
        time.sleep(seconds)
        buzzer_hw.off()
    else:
        print(f"[sim] BUZZER for {seconds}s")


# ── MQTT ────────────────────────────────────────────────────────────────────
def on_connect(client, userdata, flags, rc, properties=None):
    print(f"Connected to MQTT Broker (rc={rc})")
    client.subscribe(CONTROL_TOPIC)


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
        if payload.get("buzzer"):
            print("Buzzer triggered via MQTT control.")
            fire_buzzer(2.0)
    except Exception as e:  # noqa: BLE001
        print(f"Bad control message: {e}")


def main() -> None:
    global _last_motion_ts
    try:
        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message

    print(f"Connecting to MQTT: {MQTT_BROKER}:{MQTT_PORT}  |  "
          f"Buzzer threshold: {TEMP_BUZZER_THRESHOLD}°C")
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.loop_start()

    print(f"Running. Publish every {PUBLISH_INTERVAL}s. "
          f"Buzzer fires when temp > {TEMP_BUZZER_THRESHOLD}°C.")

    if has_gpio and led_green:
        led_green.on()

    while True:
        temp, hum = read_temperature_humidity()
        motion_active = read_motion()
        noise = read_sound()

        if motion_active:
            _last_motion_ts = int(time.time())

        buzzer_on = temp is not None and temp > TEMP_BUZZER_THRESHOLD
        if buzzer_on:
            fire_buzzer(1.0)

        payload = {
            "temperature": temp,
            "humidity": hum,
            "motion": "Active" if motion_active else "Inactive",
            "last_motion": _last_motion_ts,
            "noise": noise,
            "mode": "Temperature",
            "buzzer": "ON" if buzzer_on else "OFF",
            "timestamp": int(time.time()),
        }
        client.publish(TELEMETRY_TOPIC, json.dumps(payload))
        print(f"Published: temp={temp}°C  hum={hum}%  "
              f"motion={'Active' if motion_active else 'Inactive'}  "
              f"buzzer={'ON' if buzzer_on else 'OFF'}")

        time.sleep(PUBLISH_INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopping.")
        if has_gpio and buzzer_hw:
            buzzer_hw.off()
