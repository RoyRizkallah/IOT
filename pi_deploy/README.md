# SentryAgent — Raspberry Pi setup (fresh SD card)

Hand this folder to whoever sets up the new SD card. It contains everything the
Pi needs to read the sensors + camera and publish to the SentryAgent broker.

## Files
- `pi_sensor_publisher.py` — reads DHT11 (temp/humidity), PIR motion, sound,
  buzzer; publishes JSON to MQTT `iot/pi/telemetry` every 5s.
- `pi_camera_streamer.py` — pushes JPEG frames to the PC camera relay over WS.
- `setup_pi.sh` — creates the venv and installs all required libraries.

## Hardware wiring (BCM pin numbers)
| Sensor | GPIO |
|---|---|
| DHT11 temp/humidity | 23 |
| PIR motion | 22 |
| Sound sensor (digital out) | 24 |
| Buzzer (active) | 18 (pin 12) |
| Status LEDs (optional) | green 13, red 5, blue 19, white 26 |
| Mode button (optional) | 6 |

Each sensor degrades to a simulated value if not wired, so it still runs.

## Step 1 — Flash the SD card (on a PC)
Use **Raspberry Pi Imager** (raspberrypi.com/software):
- Device: **Raspberry Pi 3**
- OS: **Raspberry Pi OS (32-bit)**
- Storage: the new microSD (≥16GB)
- Click the **gear ⚙ (Edit Settings)** before writing:
  - Enable **SSH** (password authentication)
  - Username: `pi`  Password: `qwerty123`
  - (Optional) set WiFi — but Ethernet to the PC is more reliable
- Write, then put the card in the Pi.

## Step 2 — Network
Connect the Pi to the PC. Easiest/most reliable: **Ethernet cable Pi → PC**,
with the PC's Internet Connection Sharing / Mobile Hotspot on so the Pi gets a
`192.168.137.x` address (the Pi is typically `192.168.137.38`, the PC/broker is
`192.168.137.1`).

## Step 3 — Copy this folder to the Pi and run setup
From the PC:
```bash
scp -r pi_deploy pi@192.168.137.38:/home/pi/iot-demo
ssh pi@192.168.137.38
cd /home/pi/iot-demo
chmod +x setup_pi.sh
./setup_pi.sh
```

## Step 4 — Run the sensors (and camera)
```bash
/home/pi/iot-demo/venv/bin/python3 -u pi_sensor_publisher.py
# in another session, optionally:
/home/pi/iot-demo/venv/bin/python3 -u pi_camera_streamer.py
```
You should see lines like:
`Published: temp=22.6°C  hum=49%  motion=Active  buzzer=OFF`

## Broker / app settings
- The Pi publishes to **MQTT `192.168.137.1:1883`** (set in `pi_sensor_publisher.py`).
- The PC runs Mosquitto (Docker) which also serves WebSocket on **8083** for the app.
- In the app: broker host `192.168.137.1`, port `8083`; camera host `192.168.137.1`, port `8000`.

## Notes / gotchas (learned the hard way)
- **Always run the publisher from the venv python**, not system `python3` — only
  the venv has `adafruit_dht` / `gpiozero` / `paho`.
- **Kill duplicate copies** before starting — two publishers fight over the GPIO
  pins (`GPIO busy`) and fall back to simulation.
- Reboot the Pi with `sudo reboot` (clean), not by pulling power — repeated hard
  power-cuts can corrupt the SD card (which is what killed the previous one).
