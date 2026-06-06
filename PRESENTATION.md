# SentryAgent — University Presentation Setup

This is the day-of checklist for running the full system **laptop + Raspberry Pi
+ phone on the same Wi‑Fi**. It covers the sensor bridge and the live camera.

---

## 1. Topology

```
                Wi‑Fi (same network)
   ┌───────────────┐         ┌──────────────────────────────────────────┐
   │ Raspberry Pi  │         │ Laptop (Docker)                          │
   │               │         │                                          │
   │ sensors  ─────┼── MQTT ─┼─▶ broker (:1883) ─▶ agent ─▶ Ollama LLM  │
   │  iot/pi/      │         │                     │        + SQLite     │
   │  telemetry    │         │                     ▼                     │
   │               │         │              home/agent/* (state,        │
   │ camera   ─────┼── WS ───┼─▶ camera relay (:8000)   decisions,chat) │
   │  /ws/camera/  │         │        │                                 │
   │  stream       │         │        ▼                                 │
   └───────────────┘         │   /ws/camera/view ───────────────────────┼──▶ Phone (app)
                             └──────────────────────────────────────────┘
                                          ▲
                                          └── MQTT + camera ── Phone (app)
```

- **Broker + agent + camera relay + Ollama** all run on the **laptop** (Docker).
- The **Pi** only *sends* data: sensor telemetry over MQTT, camera frames over WebSocket.
- The **phone app** connects to the laptop for both MQTT and the camera.

---

## 2. What we adjusted on our side (already done)

You do **not** need to change the Pi's data format. The backend was adapted to it:

| Pi sends | Our backend now does |
| --- | --- |
| One combined JSON on `iot/pi/telemetry` | **Pi bridge** splits it into motion / sound / temperature readings and runs the normal classify → LLM → SQLite pipeline |
| `motion: "Active"/"Inactive"` | → motion event when active |
| `noise: 750/120` (binary sound sensor) | → `≥400` maps to an ALERT-level dB; below is idle (tune via `pi_bridge.noise_threshold`) |
| `temperature` | → passes straight through |
| `humidity` | ignored by the agent (no model field) |
| Camera JPEG over `ws://…/ws/camera/stream` | **Camera relay** receives it and re-broadcasts to the app at `/ws/camera/view` |

The bridge is on by default (`config.yaml → pi_bridge.enabled: true`).

---

## 3. The only Pi-side settings (network address, not code logic)

The Pi scripts default to talking to `localhost`. Point them at the **laptop's IP**:

1. **Find the laptop IP** (on the laptop):
   - Windows: `ipconfig` → IPv4 Address (e.g. `192.168.1.50`)
   - macOS/Linux: `ipconfig getifaddr en0` / `hostname -I`

2. **Sensor publisher** — edit `pi_sensor_publisher.py` line 53:
   ```python
   MQTT_BROKER = "192.168.1.50"   # ← laptop IP (was "localhost")
   ```

3. **Camera streamer** — no edit needed, just pass the host:
   ```bash
   python3 pi_camera_streamer.py --host 192.168.1.50 --port 8000
   ```

---

## 4. Run order

### On the laptop

```bash
cd sentry_agent

# First run only (pulls the model into the Ollama container):
docker compose --profile with-ollama up --build

# Already have native Ollama running on the laptop? Just:
# docker compose up --build
```

This starts: **broker (1883)**, **agent (LLM + SQLite)**, and **camera relay
(8000)** — no fake data. The Pi is the data source.

> Tip: for a **laptop-only** dry run (no Pi), add the simulator:
> `docker compose --profile mock up --build`. Don't use it during the live demo
> or it will publish alongside the real Pi.

**Open the laptop firewall** for inbound `1883` (MQTT) and `8000` (camera) so the
Pi and phone can reach them. On Windows the first run usually triggers a prompt —
click *Allow on private networks*.

Quick browser check (laptop): open `http://localhost:8000/` — you should see the
live camera preview once the Pi is streaming.

### On the Pi

```bash
python3 pi_sensor_publisher.py            # broker IP set in the file
python3 pi_camera_streamer.py --host 192.168.1.50 --port 8000
```

### On the phone (app)

1. Settings → **Connection → MQTT broker** → set host to the **laptop IP**, port `1883`.
2. The **Camera** tab reuses the broker host automatically (port `8000`). Override
   only if the relay runs elsewhere (Camera tab → tune icon).

---

## 5. Verification checklist

- [ ] Laptop: `docker compose ps` shows `broker`, `agent`, `camera` (and `ollama` if used) **up**.
- [ ] Laptop browser: `http://localhost:8000/status` shows `producer_connected: true` once the Pi camera is running.
- [ ] Phone: Dashboard pill shows **LIVE** (MQTT connected).
- [ ] Phone: trigger motion on the Pi → an event appears in **History**, and a Yellow/Red event produces an entry in **Reasoning** (the LLM decision).
- [ ] Phone: **Camera** tab shows **LIVE** with a moving picture.
- [ ] Phone: **Agent** tab → ask "what just happened?" → the agent answers from real history.

---

## 6. Troubleshooting

| Symptom | Fix |
| --- | --- |
| App pill stuck on CONNECTING / NO BROKER | Wrong host, or laptop firewall blocking 1883. Use the laptop's **LAN IP**, not `localhost`/`10.0.2.2` (those are for the emulator only). |
| Camera shows **NO SIGNAL** | Relay is up but the Pi isn't streaming. Start `pi_camera_streamer.py --host <laptop-ip>`; check firewall on 8000. |
| Camera **OFFLINE** | App can't reach the relay. Confirm `http://<laptop-ip>:8000/` opens from the phone's browser. |
| No events from the Pi | Confirm `MQTT_BROKER` in `pi_sensor_publisher.py` is the laptop IP. Tail the bus: `docker compose run --rm --profile tools tools mosquitto_sub -h broker -t '#' -v`. |
| Every loud sound = ALERT (too sensitive) | Raise `pi_bridge.noise_threshold` in `config.yaml`, or set `SENTRY_PI_NOISE_THRESHOLD`. |
| LLM slow on first event | The model loads on first call (10–30s). Pre-warm by triggering one event a minute before presenting. |
| Want to demo without the Pi | Add the simulator: `docker compose --profile mock up`. It mirrors the Pi's sensors (motion, sound, temperature). |

---

## 7. One-line recap of the contract

- **Sensors:** Pi → `iot/pi/telemetry` (combined JSON) → bridge → agent.
- **Camera:** Pi → `ws://<laptop>:8000/ws/camera/stream` → relay → app `…/ws/camera/view`.
- **App ↔ agent:** standard `home/#` MQTT topics on the laptop broker.
