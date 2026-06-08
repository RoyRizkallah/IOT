"""Deploy updated pi_sensor_publisher.py with buzzer support to the Pi."""
import paramiko

UPDATED_SCRIPT = r'''#!/usr/bin/env python3
"""
Raspberry Pi Sensor & Control Publisher (Direct Breadboard Connection - Mode Indicator System)
Grove Button:
Cycles through:
Temperature -> Humidity -> Motion -> Temperature

Pin Distribution:
- Green LED  (GPIO 13): Power indicator, always ON.
- Red LED    (GPIO 5):  Temperature indicator. Blinks based on current temperature in Temp Mode.
- Blue LED   (GPIO 19): Humidity indicator. Blinks based on current humidity in Humidity Mode.
- White LED  (GPIO 26): Motion indicator. Blinks rapidly on motion in Motion Mode.
- Buzzer     (GPIO 17): Active buzzer. Beeps when temperature exceeds TEMP_BUZZER_THRESHOLD.
- DHT11      (GPIO 23): Reads temperature & humidity.
- PIR Motion (GPIO 22): Detects motion.
- Grove Button (GPIO 6): Mode Selection.
- Sound Sensor (GPIO 27): Available for future use.

Dependencies:
    pip install paho-mqtt adafruit-circuitpython-dht gpiozero spidev
"""

import json
import time
import threading
import paho.mqtt.client as mqtt

try:
    import RPi.GPIO as GPIO
except ImportError:
    GPIO = None

try:
    import board
    import adafruit_dht
    dht_device = adafruit_dht.DHT11(board.D23)
    print("DHT11 sensor initialized on GPIO 23.")
except Exception as e:
    print(f"Could not initialize DHT11 sensor: {e}. Running DHT in mock/simulation mode.")
    dht_device = None

try:
    from gpiozero import LED, Button, MotionSensor, Buzzer
    has_gpio = True
except ImportError:
    print("gpiozero library not found. Running in mock/simulation mode.")
    has_gpio = False


# ==================== CONFIGURATION ====================
MQTT_BROKER              = "localhost"
MQTT_PORT                = 1883
MQTT_TOPIC               = "iot/pi/telemetry"
MQTT_CONTROL_TOPIC       = "iot/pi/control"
PUBLISH_INTERVAL         = 5.0   # seconds

# Hardware pins
DHT_PIN          = 23
PIR_MOTION_PIN   = 22
BUTTON_PIN       = 6
SOUND_PIN        = 27
LED_GREEN_PIN    = 13
LED_RED_PIN      = 5
LED_BLUE_PIN     = 19
LED_WHITE_PIN    = 26
BUZZER_PIN       = 17   # Active buzzer on GPIO 17

# Buzzer settings
TEMP_BUZZER_THRESHOLD = 35.0   # °C — buzz when temperature exceeds this value
BUZZER_BEEPS          = 3      # number of beeps per alert
BUZZER_ON_TIME        = 0.2    # seconds each beep is ON
BUZZER_OFF_TIME       = 0.15   # seconds between beeps
BUZZER_COOLDOWN       = 30.0   # seconds before buzzer can trigger again
# ========================================================

led_green = led_red = led_blue = led_white = None
buzzer_hw = None
button = None
motion = None
sound_sensor = None

current_mode  = 0
mode_names    = ["Temperature", "Humidity", "Motion"]
led_green_state = "ON"
led_red_state   = "OFF"
led_blue_state  = "OFF"
led_white_state = "OFF"

last_mode              = -1
last_motion_time       = 0.0
last_dht_warning_time  = 0.0
last_noise_warning_time = 0.0
noise_latch            = False
last_buzzer_time       = 0.0   # tracks cooldown
buzzer_state           = "OFF" # reported in telemetry

if has_gpio:
    try:
        led_green  = LED(LED_GREEN_PIN)
        led_red    = LED(LED_RED_PIN)
        led_blue   = LED(LED_BLUE_PIN)
        led_white  = LED(LED_WHITE_PIN)
        buzzer_hw  = Buzzer(BUZZER_PIN)

        led_red.off(); led_blue.off(); led_white.off()
        led_green.on()
        buzzer_hw.off()

        button = Button(BUTTON_PIN, pull_up=True)
        motion = MotionSensor(PIR_MOTION_PIN)

        if GPIO is not None:
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(SOUND_PIN, GPIO.IN)

        print("Hardware: GPIO pins initialized successfully.")
    except Exception as e:
        print(f"Error initializing GPIO: {e}. Falling back to simulation.")
        has_gpio = False


def _buzzer_sequence():
    """Run buzzer beep sequence in a background thread (non-blocking)."""
    global buzzer_state
    buzzer_state = "ON"
    for _ in range(BUZZER_BEEPS):
        if has_gpio and buzzer_hw:
            try:
                buzzer_hw.on()
            except Exception:
                pass
        time.sleep(BUZZER_ON_TIME)
        if has_gpio and buzzer_hw:
            try:
                buzzer_hw.off()
            except Exception:
                pass
        time.sleep(BUZZER_OFF_TIME)
    buzzer_state = "OFF"


def maybe_buzz_for_temp(temp):
    """Trigger buzzer if temperature is above threshold and cooldown has elapsed."""
    global last_buzzer_time, buzzer_state
    if temp is None:
        return
    now = time.time()
    if temp > TEMP_BUZZER_THRESHOLD and (now - last_buzzer_time) >= BUZZER_COOLDOWN:
        last_buzzer_time = now
        print(f"[BUZZER] Temp={temp}°C > {TEMP_BUZZER_THRESHOLD}°C — triggering alert buzzer!")
        t = threading.Thread(target=_buzzer_sequence, daemon=True)
        t.start()


def update_led_behaviors(temp, hum, motion_status):
    global led_green_state, led_red_state, led_blue_state, led_white_state, last_mode

    led_green_state = "ON"
    if has_gpio and led_green:
        try: led_green.on()
        except Exception: pass

    if current_mode != last_mode:
        last_mode = current_mode
        if has_gpio:
            try: led_red.off(); led_blue.off(); led_white.off()
            except Exception: pass

    # Red LED — Temperature Mode
    target_red_state = "OFF"; red_interval = None
    if current_mode == 0:
        t = temp if temp is not None else 23.0
        if t <= 20:   target_red_state = "BLINKING_SLOW";      red_interval = 1.0
        elif t <= 25: target_red_state = "BLINKING_MEDIUM";     red_interval = 0.5
        elif t <= 30: target_red_state = "BLINKING_FAST";       red_interval = 0.25
        else:         target_red_state = "BLINKING_VERY_FAST";  red_interval = 0.1

    if led_red_state != target_red_state:
        led_red_state = target_red_state
        if has_gpio and led_red:
            try:
                led_red.off()
                if red_interval: led_red.blink(on_time=red_interval, off_time=red_interval, background=True)
            except Exception as e: print(f"Red LED error: {e}")

    # Blue LED — Humidity Mode
    target_blue_state = "OFF"; blue_interval = None
    if current_mode == 1:
        h = hum if hum is not None else 45.0
        if h <= 30:   target_blue_state = "BLINKING_SLOW";      blue_interval = 1.0
        elif h <= 50: target_blue_state = "BLINKING_MEDIUM";     blue_interval = 0.5
        elif h <= 70: target_blue_state = "BLINKING_FAST";       blue_interval = 0.25
        else:         target_blue_state = "BLINKING_VERY_FAST";  blue_interval = 0.1

    if led_blue_state != target_blue_state:
        led_blue_state = target_blue_state
        if has_gpio and led_blue:
            try:
                led_blue.off()
                if blue_interval: led_blue.blink(on_time=blue_interval, off_time=blue_interval, background=True)
            except Exception as e: print(f"Blue LED error: {e}")

    # White LED — Motion Mode
    target_white_state = "OFF"; white_interval = None
    if current_mode == 2 and motion_status == "Active":
        target_white_state = "BLINKING_FAST"; white_interval = 0.1

    if led_white_state != target_white_state:
        led_white_state = target_white_state
        if has_gpio and led_white:
            try:
                led_white.off()
                if white_interval: led_white.blink(on_time=white_interval, off_time=white_interval, background=True)
            except Exception as e: print(f"White LED error: {e}")


def is_button_pressed():
    if has_gpio and button:
        try: return button.is_pressed
        except Exception: pass
    return False


def read_sensors():
    global last_motion_time, last_dht_warning_time, last_noise_warning_time, noise_latch
    temp = hum = noise = None
    motion_status = "Inactive"

    if dht_device:
        for _ in range(3):
            try:
                temp = dht_device.temperature
                hum  = dht_device.humidity
                break
            except Exception:
                time.sleep(0.2)

    if has_gpio and motion:
        try:
            if motion.motion_detected:
                motion_status = "Active"
                last_motion_time = time.time()
        except Exception: pass
    elif not has_gpio:
        if (int(time.time()) // 4) % 2 == 1:
            motion_status = "Active"
            last_motion_time = time.time()

    if has_gpio and GPIO:
        try:
            if GPIO.input(SOUND_PIN) == 1: noise_latch = True
            noise = 750 if noise_latch else 120
        except Exception: pass

    now = time.time()
    if (temp is None or hum is None) and now - last_dht_warning_time > 10:
        print("Warning: DHT11 read failed.")
        last_dht_warning_time = now
    if noise is None and now - last_noise_warning_time > 10:
        print("Warning: Sound sensor read failed.")
        last_noise_warning_time = now

    return temp, hum, motion_status, noise


def publish_telemetry(client):
    global noise_latch
    temp, hum, motion_status, noise = read_sensors()

    # --- Buzzer check ---
    maybe_buzz_for_temp(temp)

    payload = {
        "temperature": temp,
        "humidity":    hum,
        "motion":      motion_status,
        "last_motion": int(last_motion_time) if last_motion_time > 0.0 else None,
        "noise":       noise,
        "mode":        mode_names[current_mode],
        "led_green":   led_green_state,
        "led_red":     led_red_state,
        "led_blue":    led_blue_state,
        "led_white":   led_white_state,
        "buzzer":      buzzer_state,
        "buzzer_threshold": TEMP_BUZZER_THRESHOLD,
    }
    client.publish(MQTT_TOPIC, json.dumps(payload))
    print(f"Published: temp={temp}°C  hum={hum}%  motion={motion_status}  buzzer={buzzer_state}")
    noise_latch = False


def on_connect(client, userdata, flags, rc, properties=None):
    print(f"Connected to MQTT Broker (rc={rc})")
    client.subscribe(MQTT_CONTROL_TOPIC)


def on_message(client, userdata, msg):
    global current_mode, TEMP_BUZZER_THRESHOLD
    payload = msg.payload.decode()
    print(f"Control command: {payload}")
    try:
        data = json.loads(payload)
        if "mode" in data and data["mode"] in mode_names:
            current_mode = mode_names.index(data["mode"])
            print(f"Mode → {mode_names[current_mode]}")
            temp, hum, motion_status, _ = read_sensors()
            update_led_behaviors(temp, hum, motion_status)
            publish_telemetry(client)
        if "buzzer_threshold" in data:
            TEMP_BUZZER_THRESHOLD = float(data["buzzer_threshold"])
            print(f"Buzzer threshold updated → {TEMP_BUZZER_THRESHOLD}°C")
    except Exception as e:
        print("Error processing control command:", e)


def main():
    global current_mode
    print(f"Connecting to MQTT: {MQTT_BROKER}:{MQTT_PORT}  |  Buzzer threshold: {TEMP_BUZZER_THRESHOLD}°C")

    try:
        client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        client = mqtt.Client()

    client.on_connect = on_connect
    client.on_message = on_message

    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        client.loop_start()
    except Exception as e:
        print(f"Failed to connect to broker: {e}")
        return

    temp, hum, motion_status, _ = read_sensors()
    update_led_behaviors(temp, hum, motion_status)

    print(f"Running. Publish every {PUBLISH_INTERVAL}s. Buzzer fires when temp > {TEMP_BUZZER_THRESHOLD}°C.")

    last_button_state = False
    last_publish_time = 0

    try:
        while True:
            now = time.time()
            temp, hum, motion_status, _ = read_sensors()
            update_led_behaviors(temp, hum, motion_status)

            btn = is_button_pressed()
            if btn and not last_button_state:
                current_mode = (current_mode + 1) % 3
                print(f"Button: mode → {mode_names[current_mode]}")
                update_led_behaviors(temp, hum, motion_status)
                publish_telemetry(client)
                last_publish_time = now
            last_button_state = btn

            if now - last_publish_time >= PUBLISH_INTERVAL:
                publish_telemetry(client)
                last_publish_time = now

            time.sleep(0.05)

    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        client.loop_stop()
        client.disconnect()
        if has_gpio:
            try:
                led_green.close(); led_red.close(); led_blue.close()
                led_white.close(); buzzer_hw.close()
                button.close(); motion.close()
                if GPIO: GPIO.cleanup()
            except Exception: pass

if __name__ == "__main__":
    main()
'''

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect('192.168.137.38', username='pi', password='qwerty123', timeout=15)

def run(cmd, timeout=20):
    _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    return (stdout.read() + stderr.read()).decode('utf-8', errors='replace').strip()

# Backup the original
print("Backing up original...")
print(run("cp ~/iot-demo/pi_sensor_publisher.py ~/iot-demo/pi_sensor_publisher.py.bak"))

# Write new file
sftp = client.open_sftp()
import io
sftp.putfo(io.BytesIO(UPDATED_SCRIPT.encode()), '/home/pi/iot-demo/pi_sensor_publisher.py')
sftp.close()
print("Deployed pi_sensor_publisher.py with buzzer support.")

# Verify it's there
print("Lines:", run("wc -l ~/iot-demo/pi_sensor_publisher.py"))
print("Buzzer pin config:", run("grep 'BUZZER' ~/iot-demo/pi_sensor_publisher.py | head -5"))

client.close()
print("\nDone! Buzzer added on GPIO 17, triggers when temp > 35 degrees C (30s cooldown).")
