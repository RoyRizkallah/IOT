# SentryAgent

The on-device reasoning brain of the SentryAgent home-security system.

Receives a sensor event (e.g. *"motion at the back door at 3am"*), reasons
about whether it's a real threat or just the cat, and emits a structured
decision the Flutter app + the home automation layer can act on.

Runs locally against [Ollama](https://ollama.com/) — no cloud, no API key,
no data leaves your house. Wires to MQTT so the Flutter app, the agent,
and the (eventually) Pi-based sensors all speak the same language.

---

## What's in here

```
sentry_agent/
├── pyproject.toml          # deps + entrypoint
├── config.yaml             # runtime config (LLM, thresholds, MQTT)
├── docker-compose.yml      # broker + sensors + agent (+ optional ollama)
├── Dockerfile              # multi-purpose image (serve / mock / decide)
├── docker/
│   └── mosquitto/
│       └── mosquitto.conf
├── sentry/
│   ├── models.py           # Pydantic models — mirror the Dart side
│   ├── tools.py            # tool registry the LLM can call
│   ├── prompts/            # Jinja2 prompt templates
│   ├── prompt.py
│   ├── llm/                # LLM provider abstraction (Ollama)
│   ├── agent.py            # decision engine
│   ├── event_classifier.py # raw reading → SecurityEvent rules
│   ├── orchestrator.py     # MQTT-driven service: sub, classify, decide, pub
│   ├── mqtt/               # MQTT bus + topic conventions
│   ├── sensors/
│   │   └── mock.py         # fake sensor publisher (default | suspicious | flapping)
│   ├── config.py           # YAML + env → typed config
│   └── __main__.py         # `sentry` CLI: decide | serve | mock | version
└── tests/
    ├── fixtures/           # ready-made DecisionRequests
    ├── test_smoke.py       # 15 — engine + tools + prompts
    ├── test_classifier.py  # 18 — classifier rules
    ├── test_mqtt.py        # 18 — topic routing + payload codec
    └── test_orchestrator.py#  6 — orchestrator with stubbed bus + LLM
```

`pytest` runs all 74 tests in under a second. None of them needs Docker,
MQTT, or Ollama.

---

## MQTT topic contract

| Topic                    | Direction           | Payload                   | Notes                     |
|--------------------------|---------------------|---------------------------|---------------------------|
| `home/sensors/<type>`    | sensors → broker    | `SensorReading`           | one of motion/sound/door/temperature |
| `home/events`            | agent → broker      | `SecurityEvent`           | derived from raw readings |
| `home/agent/state`       | agent → broker      | `SecurityState`           | retained, every ~5 s      |
| `home/agent/decision`    | agent → broker      | `AgentDecision`           | one per LLM run           |
| `home/agent/chat/out`    | agent → broker      | `ChatMessage`             | reply to a user chat msg  |
| `home/agent/replay`      | agent → broker      | `{state, events, decisions, chat}` | bulk dump on request |
| `home/control/arm`       | app → broker        | `{"armed": bool}`         | flips orchestrator armed  |
| `home/control/siren`     | agent / app → broker| `{"action": "trigger"\|"stop", "reason": ...}` |  |
| `home/control/chat/in`   | app → broker        | `ChatMessage`             | user chat msg to the agent |
| `home/control/replay`    | app → broker        | `{}`                      | "send me the current world state" |

Schemas are the Pydantic models in `sentry/models.py`. Names + casing
match the Dart classes 1:1 so JSON flows through unchanged.

---

## Run paths

### A. One command — full stack, zero host install (recommended)

```powershell
cd sentry_agent
docker compose --profile with-ollama up --build
```

That's it. Compose will:

1. Start the **Mosquitto broker** (`sentry-broker`).
2. Start **mock sensors** (`sentry-sensors`) publishing realistic scenarios.
3. Start **Ollama** (`sentry-ollama`) and run a one-shot **`ollama-init`**
   service that pulls `qwen2.5:7b-instruct` if not already cached.
4. Start the **agent** (`sentry-agent`) which subscribes to MQTT, persists
   to `/data/sentry.db` (a named volume — survives `compose down`), and
   reasons over Ollama at `http://ollama:11434`.

To override the model:

```powershell
$Env:SENTRY_OLLAMA_MODEL="llama3.2:3b"
docker compose --profile with-ollama up --build
```

To stop everything (data is preserved):

```powershell
docker compose --profile with-ollama down
```

To wipe everything (DB, model cache, broker history):

```powershell
docker compose --profile with-ollama down -v
```

### B. Native Ollama on host (faster, uses GPU directly)

If you already run Ollama natively, skip the profile — the agent will
talk to `host.docker.internal:11434` automatically:

```powershell
ollama pull qwen2.5:7b-instruct          # one-time
cd sentry_agent
docker compose up --build
```

### C. Watching / driving the bus

```powershell
# Tail every MQTT message
docker compose run --rm tools mosquitto_sub -h broker -t 'home/#' -v

# Arm the system
docker compose run --rm tools mosquitto_pub -h broker -t home/control/arm -m '{\"armed\":true}'

# Switch scenarios
docker compose stop sensors
docker compose run --rm sensors mock --scenario suspicious
```

### D. Convenience wrapper scripts (optional)

If you want a friendlier console (probes for native Ollama, prints
status summaries, can launch Flutter), use the wrapper scripts at the
**project root**:

```powershell
.\start.ps1                  # Windows
.\start.ps1 -LaunchApp       # also `flutter run` afterwards
.\stop.ps1                   # tear down
.\stop.ps1 -Wipe             # also drop volumes
```

Linux/macOS: `./start.sh` and `./stop.sh`.

### E. Local Python (no Docker)

```powershell
cd C:\IOT_Project\sentry_agent
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[dev]"
pytest                              # 57 passed in ~0.5s
```

Then in three separate terminals:

```powershell
# 1. Run a broker — Mosquitto, Docker, or `mosquitto -p 1883`
docker run --rm -p 1883:1883 eclipse-mosquitto:2

# 2. Run mock sensors
sentry mock --scenario default

# 3. Run the agent (needs Ollama running)
sentry serve
```

### F. One-shot decision (no broker required)

Run the agent on a single fixture file and print the decision:

```powershell
sentry decide tests\fixtures\3am_back_door.json
```

Useful for prompt iteration — you skip MQTT entirely.

---

## Environment variables

These all override the matching `config.yaml` settings; Docker compose uses
them to point services at the right host.

| Var                       | Effect                              |
|---------------------------|-------------------------------------|
| `SENTRY_MQTT_HOST`        | broker host (default `localhost`)   |
| `SENTRY_MQTT_PORT`        | broker port (default `1883`)        |
| `SENTRY_OLLAMA_BASE_URL`  | Ollama URL (default `http://localhost:11434`) |
| `SENTRY_OLLAMA_MODEL`     | model tag (default `qwen2.5:7b-instruct`) |
| `SENTRY_DB_PATH`          | SQLite DB file (default `data/sentry.db`, container uses `/data/sentry.db`) |
| `SENTRY_LOG_LEVEL`        | `DEBUG` / `INFO` / `WARNING`        |

---

## How the orchestrator decides what to decide

```
sensor msg ─► classifier ─► severity = safe | warning | alert
                            │
                            └─► safe       → log to home/events, done.
                            └─► warning+   → enqueue + run engine.decide()
                                            → publish home/agent/decision
                                            → if action == trigger_siren:
                                                publish home/control/siren
```

The classifier is dumb-on-purpose (`event_classifier.py`): it just
applies thresholds + time-of-day + armed-state rules. The LLM gets only
the events worth its attention. Everything else flows straight through
to the event log.

A bounded `asyncio.Queue` (`decision_queue_size=10`) sits between the
sensor handler and the LLM worker, so a flood of events can't OOM the
process — overflowed events are dropped with a warning.

---

## Persistence (SQLite)

The agent writes to a single SQLite file (`data/sentry.db` locally,
`/data/sentry.db` in Docker). Four tables, one JSON-payload column each
so the schema doesn't need to change every time the Pydantic model does:

| Table            | What's in it                                |
|------------------|---------------------------------------------|
| `events`         | every `SecurityEvent` emitted by classifier |
| `decisions`      | every `AgentDecision` from the LLM          |
| `chat_messages`  | full chat history (user + agent)            |
| `state_latest`   | single-row upsert of the latest `SecurityState` |

On startup the orchestrator hydrates its in-memory deques from the most
recent N rows (`storage.history_load_limit` in `config.yaml`), so the
first replay request from the Flutter app returns historical context
even after a fresh container start.

Inspect the DB while the stack is running:

```powershell
docker exec -it sentry-agent sqlite3 /data/sentry.db ".tables"
docker exec -it sentry-agent sqlite3 /data/sentry.db "SELECT id, severity FROM events ORDER BY timestamp DESC LIMIT 10;"
```

---

## What's next

This package is **complete for Phase 2a + 2b**:

- ✅ MQTT plumbing
- ✅ Local-LLM agent with tool calls
- ✅ Mock sensors with scenario modes
- ✅ Containerised end-to-end stack

The next moves:

- **Flutter** — wire `MqttDataSource` against the same topic contract, so
  the live app reads from the broker instead of the in-memory mock.
- **Phase 3 (Pi)** — replace `sentry mock` with `pi_sensors.py` reading
  GPIO pins. The orchestrator + Flutter app don't change at all.
