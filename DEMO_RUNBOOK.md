# SentryAgent — Demo Day Runbook

Local-broker setup. Nothing depends on the internet. The Pi is the only
hardware variable; everything else is already verified working.

```
Pi (Ethernet) ──► Mosquitto on PC (192.168.137.1) ──► Agent (Docker)
                          │
            phone (on PC hotspot WiFi) ──► broker WS :8083 + camera :8000
```

---

## The 4 steps on demo day

### 1. Network
- Turn **ON** the PC Mobile Hotspot (Win settings → Mobile hotspot).
- Plug the **Pi into the PC by Ethernet cable**. Power the Pi on.
- The Pi gets `192.168.137.38`; the PC/broker is `192.168.137.1`.

### 2. Backend (on the PC)
```powershell
cd c:\IOT_Project\sentry_agent
docker compose up -d              # broker + agent + camera + ollama
docker compose stop sensors       # IMPORTANT: stop the MOCK so it doesn't
                                  # mix fake data with the real Pi
```
Verify all healthy: `docker ps`

### 3. The Pi — ONE command
```powershell
cd c:\IOT_Project
python pi_launch.py
```
This waits for the Pi, frees the GPIO pins, points the publisher at
`192.168.137.1:1883`, launches it via the **venv** python (the fix that made
sensors read real values instead of `null`), starts the camera, and confirms
the PC receives data over the phone's WebSocket path (8083).

Expect to see real readings, e.g. `temp=22.6°C  hum=49%  motion=Active`, and
`RESULT: LIVE — the phone will see this data.`

### 4. The phone
- Join the PC's **hotspot WiFi** (it will say "no internet" — that's fine).
- In the app's **Settings**:
  - Broker host: **`192.168.137.1`**
  - Broker port: **`8083`**   (WebSocket)
  - Camera host: **`192.168.137.1`**, port **`8000`**
- Dashboard should show live sensors; History fills via replay.

---

## Why these exact values (so nothing surprises you)

- **Broker = local Mosquitto on the PC.** No public broker, no internet. Data
  stays on the hotspot LAN.
- **Pi/agent use TCP 1883; the phone uses WebSocket 8083.** Same broker, two
  protocols. 8083 is used because the app only treats {8000,8080,8083,8084} as
  WebSocket ports — 8000 is the camera, 8080 is held by Docker/WSL, so 8083.
  (Mapping `8083:9001` lives in `sentry_agent/docker-compose.yml`.)
- **Publisher MUST run from `venv/bin/python3`.** Only the venv has
  `board` / `adafruit_dht` / `gpiozero`. System python → null sensors.
- **Kill orphans first.** Duplicate publisher/camera processes hold the GPIO
  pins (`GPIO busy`) → simulation mode. `pi_launch.py` handles this.

---

## Fallback (no Pi / Pi won't cooperate)

The whole system runs on simulated sensors — no hardware:
```powershell
cd c:\IOT_Project\sentry_agent
docker compose --profile mock up -d sensors
```
The mock publishes temp/motion/sound; the agent reacts; the phone shows it
all. Verified working. The phone can't tell the difference. Stop it again with
`docker compose stop sensors` before reconnecting the real Pi.

---

## Quick troubleshooting

| Symptom | Cause / fix |
|---|---|
| `pi_launch.py` says "Pi not reachable" | Cable not seated, Pi off, or hotspot off. Power-cycle Pi *after* plugging the cable. |
| Sensors show `None` / null | Publisher ran under system python or a duplicate held the pins. Re-run `pi_launch.py`. |
| Phone connects but no data | Phone on the right network? Broker port must be **8083** (WS), not 1883. |
| App shows nothing & won't update | App may hold a stale saved broker in SharedPreferences — re-enter host/port in Settings. |
| Nothing on the bus at all | `docker ps` — is `sentry-broker` healthy? `docker compose up -d`. |
| Both real + fake data appear | The mock `sensors` container is still running. `docker compose stop sensors`. |

## Known facts about this environment
- Pi: Raspberry Pi 3, Raspbian Trixie, MAC `b8:27:eb:ed:13:26`, IP `192.168.137.38`, user `pi`.
- Pi project dir: `/home/pi/iot-demo/`, venv at `/home/pi/iot-demo/venv`.
- DHT11 on GPIO 23; buzzer on GPIO 18.
- The PC's hotspot gateway/broker IP is `192.168.137.1`.
