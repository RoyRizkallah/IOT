# SentryAgent · IoT Home Security

A local, AI-powered home security system. A Raspberry Pi reads sensors
(motion, door, sound, temperature), an on-device LLM agent reasons about
each event ("real intruder or just the cat?"), and a polished Flutter
mobile app shows what's happening — live, with chat-style reasoning.

No cloud. No API key. No data leaves your house.

```
┌──────────────────┐    MQTT    ┌──────────────────┐    MQTT    ┌──────────────────┐
│  Raspberry Pi    │  ───────►  │  SentryAgent     │  ───────►  │  Flutter app     │
│  (sensors)       │            │  (Python + LLM)  │  ◄───────  │  (live dashboard)│
└──────────────────┘            └──────────────────┘            └──────────────────┘
                                       │
                                       ▼
                                ┌──────────────┐
                                │  Ollama      │
                                │  (local LLM) │
                                └──────────────┘
```

## Repo layout

```
.
├── sentry_agent/         # Python backend  — MQTT orchestrator, LLM agent, SQLite
│   ├── sentry/           # source
│   ├── tests/            # 74 tests, runs in ~0.5s
│   ├── docker-compose.yml
│   └── README.md         # ← deep dive on the backend
├── sentryagent_app/      # Flutter app    — premium mobile UI, live MQTT
│   ├── lib/
│   ├── android/
│   └── README.md         # ← deep dive on the app
├── start.ps1 / start.sh  # convenience wrappers (probe Ollama, launch stack, optionally run Flutter)
├── stop.ps1  / stop.sh   # graceful teardown (`-Wipe` to drop volumes)
└── README.md             # you are here
```

## Quick start

Prereqs: Docker Desktop, Flutter SDK (only if you want to launch the app).

```powershell
# 1. Backend — broker + sensors + Ollama + agent, one command, fully self-contained
cd sentry_agent
docker compose --profile with-ollama up --build

# 2. Mobile app (separate terminal)
cd sentryagent_app
flutter pub get
flutter run
```

First run pulls the Ollama image (~4GB) and the LLM weights
(`qwen2.5:7b-instruct`, ~4.5GB) — both cached in named Docker volumes,
so subsequent runs are seconds. Everything from then on is offline.

If you already have Ollama installed natively on the host, skip the
profile flag — it's faster (GPU passthrough):

```powershell
ollama pull qwen2.5:7b-instruct
docker compose up --build
```

## What it does, end to end

1. **Sensors** publish raw readings (mock or real Pi) to `home/sensors/<type>`.
2. The **classifier** filters noise — only events at `warning` or `alert`
   reach the LLM.
3. The **agent** calls Ollama with the event + recent context + a tool
   catalogue (lookup neighbours, check schedule, request confirmation,
   trigger siren) and emits a structured `AgentDecision`.
4. The **orchestrator** persists every event, decision, chat message,
   and the latest state to **SQLite** (`/data/sentry.db`, in a named
   volume — survives container restarts).
5. The **Flutter app** subscribes to `home/agent/*` over MQTT, renders
   the dashboard / history / reasoning log / chat in real time, and can
   arm/disarm the system or chat with the agent.

## MQTT topic contract

| Topic                    | Direction        | Notes                            |
|--------------------------|------------------|----------------------------------|
| `home/sensors/<type>`    | sensors → broker | motion / sound / door / temperature |
| `home/events`            | agent  → broker  | classified `SecurityEvent`s      |
| `home/agent/state`       | agent  → broker  | retained heartbeat (~5 s)        |
| `home/agent/decision`    | agent  → broker  | one per LLM run                  |
| `home/agent/chat/out`    | agent  → broker  | reply to a user chat msg         |
| `home/agent/replay`      | agent  → broker  | bulk dump on request             |
| `home/control/arm`       | app    → broker  | `{"armed": bool}`                |
| `home/control/siren`     | agent / app → broker | `{"action": "trigger" \| "stop"}` |
| `home/control/chat/in`   | app    → broker  | user chat msg to the agent       |
| `home/control/replay`    | app    → broker  | "send me the current world state" |

JSON schemas are the Pydantic models in
[`sentry_agent/sentry/models.py`](sentry_agent/sentry/models.py); the
Dart side mirrors them 1:1 in
[`sentryagent_app/lib/data/models/security_state.dart`](sentryagent_app/lib/data/models/security_state.dart).

## Tech stack

- **Backend**: Python 3.12, Pydantic v2, aiomqtt, aiosqlite, Jinja2,
  httpx, Typer, pytest
- **LLM**: Ollama (Qwen 2.5 7B Instruct by default — swap freely)
- **Broker**: Eclipse Mosquitto 2
- **Mobile**: Flutter 3 + Riverpod, `mqtt_client`, `fl_chart`,
  `google_fonts`, `shared_preferences`
- **Persistence**: SQLite (WAL mode), one JSON-payload column per row
  so the schema doesn't break as Pydantic models evolve
- **Orchestration**: Docker Compose (broker + sensors + agent + optional
  Ollama, with an `ollama-init` one-shot that auto-pulls the model)

## Project status

| Component         | Status |
|-------------------|--------|
| Backend agent     | Complete — 74 tests, ruff clean |
| MQTT plumbing     | Complete — round-trips Python ↔ Flutter |
| SQLite persistence| Complete — events / decisions / chat / state |
| Mock sensors      | Complete — `default`, `suspicious`, `flapping` scenarios |
| Flutter app       | Complete — live MQTT, no mock data |
| Docker stack      | Complete — one command, model auto-pull |
| **Raspberry Pi**  | **Pending** — drop-in replacement for `sentry mock` |

The Pi work is the only remaining piece. The MQTT contract means the
agent and app don't need to change to accept real sensor data — just
implement `sentry/sensors/pi.py` reading GPIO and publishing to the
same topics the mock currently uses.

## License

MIT
