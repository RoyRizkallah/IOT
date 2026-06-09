#!/usr/bin/env bash
#
# SentryAgent — fresh Raspberry Pi setup.
#
# Run this ON THE PI after flashing a fresh Raspberry Pi OS and copying the
# pi_deploy folder to /home/pi/iot-demo. It creates the virtualenv and installs
# every library the sensor publisher + camera streamer need.
#
#   scp -r pi_deploy pi@<pi-ip>:/home/pi/iot-demo      # from the PC
#   ssh pi@<pi-ip>
#   cd /home/pi/iot-demo && chmod +x setup_pi.sh && ./setup_pi.sh
#
# Then run the sensors (see the echo at the end).
set -e

PROJECT_DIR="/home/pi/iot-demo"
VENV="$PROJECT_DIR/venv"

echo "=== 1. System packages (DHT/GPIO/camera build deps) ==="
sudo apt-get update
sudo apt-get install -y \
  python3-venv python3-pip python3-dev \
  libgpiod2 i2c-tools \
  libjpeg-dev zlib1g-dev \
  python3-picamera2 || true   # picamera2 is apt-only on Pi OS; tolerate absence

echo "=== 2. Create venv (with system site packages so picamera2 is visible) ==="
cd "$PROJECT_DIR"
python3 -m venv --system-site-packages "$VENV"

echo "=== 3. Install Python libraries into the venv ==="
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install \
  paho-mqtt \
  gpiozero \
  lgpio \
  adafruit-circuitpython-dht \
  adafruit-blinka \
  pillow \
  websockets

echo "=== 4. Quick import check ==="
"$VENV/bin/python3" - <<'PY'
mods = ["paho.mqtt.client", "gpiozero", "board", "adafruit_dht", "PIL", "websockets"]
for m in mods:
    try:
        __import__(m)
        print(f"  OK   {m}")
    except Exception as e:
        print(f"  FAIL {m}: {e}")
PY

echo ""
echo "=== DONE. To run the sensors: ==="
echo "  $VENV/bin/python3 -u $PROJECT_DIR/pi_sensor_publisher.py"
echo "=== To run the camera: ==="
echo "  $VENV/bin/python3 -u $PROJECT_DIR/pi_camera_streamer.py"
echo ""
echo "Tip: set MQTT_BROKER in pi_sensor_publisher.py to the PC's IP (default 192.168.137.1)."
