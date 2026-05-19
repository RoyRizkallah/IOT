# SentryAgent — Backend & LLM Documentation

Python service that sits between the sensors and the Flutter app.
Reads sensor events over MQTT, classifies them, asks a local LLM whether
they're real threats, persists everything to SQLite, and publishes
structured decisions + chat replies back over MQTT.

No cloud. No API key. Runs entirely on your laptop (or a Pi).

---

## Tech Stack

| Component | Library / Tool | Role |
|---|---|---|
| MQTT client | `aiomqtt ^2.3.0` | Async subscribe + publish |
| Data validation | `pydantic ^2.7.0` | Domain models, JSON serialisation |
| LLM integration | `httpx ^0.27.0` | HTTP client for Ollama API |
| Prompt templating | `jinja2 ^3.1.4` | `.j2` templates for every LLM prompt |
| SQLite | `aiosqlite ^0.20.0` | Async persistence, WAL mode |
| Config | `pyyaml ^6.0.2` | YAML config + env var overrides |
| CLI | `typer ^0.12.0` | `sentry serve / mock / decide / version` |
| Console output | `rich ^13.7.0` | Formatted tables and panels |
| Testing | `pytest ^8.3.0` + `pytest-asyncio ^0.23.0` | 74 tests, ~0.5 s |
| Linting | `ruff ^0.6.0` | All clean |
| LLM runtime | Ollama (external) | Runs `qwen2.5:7b-instruct` locally |
| Broker | Eclipse Mosquitto 2 (Docker) | MQTT message bus |

---

## Project Structure

```
sentry_agent/
├── pyproject.toml           # Dependencies + `sentry` CLI entrypoint
├── config.yaml              # Runtime config (LLM, MQTT, SQLite, thresholds)
├── Dockerfile               # Multi-purpose image: serve / mock / decide
├── docker-compose.yml       # broker + sensors + agent + optional Ollama
├── docker/
│   └── mosquitto/
│       └── mosquitto.conf
└── sentry/
    ├── __init__.py
    ├── __main__.py          # CLI: serve | mock | decide | version
    ├── config.py            # Typed config dataclasses, SENTRY_* env overrides
    ├── models.py            # Pydantic domain models (wire contract with Flutter)
    ├── event_classifier.py  # Rule-based: SensorReading → SecurityEvent
    ├── agent.py             # DecisionEngine: builds prompt, calls LLM, parses output
    ├── chat.py              # ChatService: handles one chat turn with history
    ├── orchestrator.py      # Long-running service: bus + classifier + workers + persistence
    ├── storage.py           # SQLite layer (aiosqlite, WAL, JSON-payload columns)
    ├── tools.py             # Tool catalogue the LLM can call
    ├── prompt.py            # Prompt rendering helpers
    ├── prompts/
    │   ├── system.j2        # Agent persona and tool schema
    │   ├── event_evaluation.j2  # Per-event decision prompt
    │   └── chat.j2          # Chat persona + conversation context
    ├── llm/
    │   ├── base.py          # Abstract LLMClient + ToolCall types
    │   └── ollama.py        # OllamaClient: /api/chat calls, error handling
    ├── mqtt/
    │   ├── bus.py           # MqttBus: async subscribe/publish, handler registry
    │   └── topics.py        # Topic constants + parse_sensor_topic()
    └── sensors/
        └── mock.py          # MockSensorPublisher: realistic fake readings
```

---

## Architecture

### Processing Pipeline

```
Sensor (mock or Pi)
    │  publishes to home/sensors/<type>
    ▼
MqttBus._on_message()
    │  dispatches to registered handlers
    ▼
Orchestrator._on_sensor()
    │  1. Validate + store SensorReading
    │  2. EventClassifier.classify() — fast, rule-based
    │       • severity = safe   → publish home/events, done
    │       • severity = warning|alert → enqueue for LLM
    ▼
_decision_queue (asyncio.Queue, bounded)
    │
    ▼
_decision_worker  (single serial worker — one LLM call at a time)
    │  DecisionEngine.decide()
    │   → render Jinja2 prompt (system.j2 + event_evaluation.j2)
    │   → POST /api/chat to Ollama
    │   → parse JSON output into AgentDecision
    │   → loop if LLM called a tool (tools.py)
    │
    ▼
Storage.record_decision() + publish home/agent/decision
    │
    ▼
if final_action == "trigger_siren":
    publish home/control/siren
```

### Chat Pipeline

```
Flutter app
    │  publishes to home/control/chat/in  (ChatMessage JSON)
    ▼
Orchestrator._on_chat_in()
    │  parse → Storage.record_chat(user_msg) → enqueue
    ▼
_chat_queue (separate queue — runs parallel to decisions)
    │
    ▼
_chat_worker
    │  ChatService.reply()
    │   → render chat.j2 with state + events + history
    │   → POST /api/chat to Ollama
    │   → extract {"reply": "..."} from JSON output
    │
    ▼
Storage.record_chat(agent_reply) + publish home/agent/chat/out
```

### State Heartbeat

```
_state_ticker  (every 5 s)
    │
    ├── Storage.record_state()
    └── publish home/agent/state  (retained)
```

---

## Domain Models (`sentry/models.py`)

All models are Pydantic v2. Field names match Dart 1:1 — JSON crosses
the MQTT wire unchanged.

### SensorReading
```python
SensorReading(
    type: SensorType,         # motion | sound | door | temperature
    value: float,             # dB / °C / 0.0 or 1.0 for binary sensors
    active: bool,
    timestamp: datetime,      # serialised as UTC ISO-8601
)
```

### SecurityEvent
```python
SecurityEvent(
    id: str,
    sensor: SensorType,
    severity: ThreatLevel,    # safe | warning | alert
    message: str,             # "Motion detected at the back door"
    timestamp: datetime,
    raw_value: float | None,
)
```

### AgentDecision
```python
AgentDecision(
    id: str,
    timestamp: datetime,
    severity: ThreatLevel,
    summary: str,             # one-line headline
    context: str,             # what the agent saw
    reasoning: str,           # why it decided what it did
    tools_called: list[ToolCallRecord],
    final_action: Literal[
        "ignore", "log", "notify_user",
        "request_confirmation", "trigger_siren", "auto_resolve"
    ],
    final_action_reason: str,
)
```

### ChatMessage
```python
ChatMessage(
    id: str,
    role: Literal["user", "agent"],
    text: str,
    timestamp: datetime,
    in_reply_to: str | None,   # id of the user message being answered
)
```

---

## Event Classifier (`sentry/event_classifier.py`)

Converts raw `SensorReading` → `SecurityEvent | None` using rule-based
thresholds. This is the **fast pre-filter** — the LLM only sees events the
classifier already rated `warning` or above.

| Sensor | Rule | Severity |
|---|---|---|
| Motion | Active while armed, at night | `alert` |
| Motion | Active while armed, daytime | `warning` |
| Sound | > 85 dB | `alert` |
| Sound | > 65 dB | `warning` |
| Door | Opened while armed | `alert` |
| Door | Opened while disarmed | `warning` |
| Temperature | < 0°C or > 40°C | `warning` |

Boring readings (motion inactive, normal sound, normal temperature) return
`None` — they update state silently and never touch the LLM queue.

---

## LLM Integration

### Model: Qwen 2.5 7B Instruct (default)

Run via [Ollama](https://ollama.com/). The backend talks to Ollama's
`/api/chat` endpoint with structured messages. Swap the model any time:

```yaml
# config.yaml
llm:
  model: llama3.2:3b      # lighter, ~2GB
  # model: phi3.5:3.8b    # balanced
  # model: qwen2.5:7b-instruct  # best tool calling, default
```

Or via env var: `SENTRY_OLLAMA_MODEL=llama3.2:3b`

### Prompt Templates (`sentry/prompts/`)

**`system.j2`** — Establishes the agent's persona ("SentryAgent, a home
security AI") and injects the JSON tool schema.

**`event_evaluation.j2`** — Per-decision prompt. Injects:
- Current state (armed, threat score, all sensor readings)
- The triggering event
- Recent event history (last 12 by default)
- Required output schema (structured JSON)

**`chat.j2`** — Chat persona prompt. Injects:
- Current state
- Recent events and decisions (for context-aware answers)
- Conversation history (last N turns)
- Required output schema: `{"reply": "..."}`

### Tool Calling (`sentry/tools.py`)

The LLM can call these tools before returning a final decision:

| Tool | What it does |
|---|---|
| `lookup_neighbor_activity` | Returns simulated neighbour activity log |
| `get_time_context` | Returns time of day, day of week, local time |
| `get_schedule` | Returns user's schedule (home / away / sleep) |
| `request_user_confirmation` | Escalates to user before acting |
| `trigger_siren` | Marks that the siren should be activated |

The decision worker loops until the LLM stops calling tools or hits
`max_tool_call_retries` (default: 2).

### Decision Engine Flow (`sentry/agent.py`)

1. Build system prompt from `system.j2` + tool schema.
2. Build user prompt from `event_evaluation.j2`.
3. POST to Ollama `/api/chat`.
4. Parse JSON from response. If malformed, retry with a correction prompt.
5. If LLM returned a tool call, dispatch to `tools.py`, append result,
   and call Ollama again.
6. Return `AgentDecision` on first clean structured output.

---

## Persistence (`sentry/storage.py`)

SQLite database at `data/sentry.db` locally, `/data/sentry.db` in Docker
(named volume — survives `compose down`).

### Schema

| Table | Key | What's stored |
|---|---|---|
| `events` | `id TEXT PRIMARY KEY` | `SecurityEvent` as JSON |
| `decisions` | `id TEXT PRIMARY KEY` | `AgentDecision` as JSON |
| `chat_messages` | `id TEXT PRIMARY KEY` | `ChatMessage` as JSON |
| `state_latest` | `id = 1` (single row) | Latest `SecurityState` as JSON |

Each row has one `payload TEXT` column holding the full Pydantic
`.model_dump_json()` output — schema changes never break old rows because
they're read back with `Model.model_validate_json()`.

### Startup Hydration

On startup the orchestrator calls `Storage.recent_events(limit=50)`,
`recent_decisions()`, `recent_chat()`, and `latest_state()` and loads
them into the in-memory deques. The very first MQTT replay request from
the Flutter app therefore returns real history even on a fresh container
start.

### Inspect the live DB

```bash
docker exec -it sentry-agent sqlite3 /data/sentry.db ".tables"
docker exec -it sentry-agent sqlite3 /data/sentry.db \
  "SELECT id, severity, message FROM events ORDER BY timestamp DESC LIMIT 10;"
```

---

## MQTT Topics

| Topic | Direction | Payload | Notes |
|---|---|---|---|
| `home/sensors/<type>` | sensors → agent | `SensorReading` | type = motion/sound/door/temperature |
| `home/events` | agent → app | `SecurityEvent` | every classified event |
| `home/agent/state` | agent → app | `SecurityState` | retained, every ~5 s |
| `home/agent/decision` | agent → app | `AgentDecision` | one per LLM run |
| `home/agent/chat/out` | agent → app | `ChatMessage` (role: agent) | LLM reply |
| `home/agent/replay` | agent → app | `{state, events, decisions, chat}` | bulk dump |
| `home/control/arm` | app → agent | `{"armed": bool}` | |
| `home/control/siren` | agent/app → broker | `{"action": "trigger"\|"stop"}` | |
| `home/control/chat/in` | app → agent | `ChatMessage` (role: user) | |
| `home/control/replay` | app → agent | `{}` | triggers bulk dump |

---

## Configuration (`config.yaml`)

```yaml
llm:
  provider: ollama
  model: qwen2.5:7b-instruct
  base_url: http://localhost:11434
  temperature: 0.2          # low = deterministic security decisions
  max_tokens: 800
  request_timeout_s: 90

agent:
  history_window_size: 12   # events fed to LLM as context
  max_tool_call_retries: 2  # retries on malformed JSON output
  hard_alert_threshold: 7   # score ≥ 7 skips LLM, escalates directly

mqtt:
  enabled: true
  host: localhost
  port: 1883

storage:
  db_path: data/sentry.db
  history_load_limit: 50    # rows loaded into memory on startup
  prune_max_rows: 5000      # per-table cap

logging:
  level: INFO
  rich_console: true
```

### Environment Variable Overrides

All override the matching `config.yaml` value — Docker Compose uses these:

| Variable | Effect |
|---|---|
| `SENTRY_MQTT_HOST` | Broker hostname (e.g. `broker` inside Docker) |
| `SENTRY_MQTT_PORT` | Broker port (default `1883`) |
| `SENTRY_OLLAMA_BASE_URL` | Ollama URL (e.g. `http://ollama:11434`) |
| `SENTRY_OLLAMA_MODEL` | Model tag (e.g. `llama3.2:3b`) |
| `SENTRY_DB_PATH` | SQLite file path (e.g. `/data/sentry.db`) |
| `SENTRY_LOG_LEVEL` | `DEBUG` / `INFO` / `WARNING` |

---

## Running

### Full stack (one command)

```bash
cd sentry_agent

# With containerised Ollama — fully self-contained, model is auto-pulled:
docker compose --profile with-ollama up --build

# With native Ollama installed on the host (faster, uses GPU):
ollama pull qwen2.5:7b-instruct
docker compose up --build
```

First run pulls Ollama image (~4 GB) and model weights (~4.5 GB), both
cached in named Docker volumes. Subsequent runs start in seconds.

### Individual CLI commands

```bash
cd sentry_agent
python -m venv .venv && .venv\Scripts\activate   # Windows
pip install -e ".[dev]"

# Run the full agent (needs a broker + Ollama already up):
sentry serve

# Publish mock sensor readings:
sentry mock --scenario suspicious --speed 2.0

# One-shot decision on a fixture file (no MQTT needed):
sentry decide tests/fixtures/3am_back_door.json

# Show version:
sentry version
```

### Tests

```bash
pytest                    # 74 tests, ~0.5 s
pytest tests/test_storage.py -v    # storage layer only
pytest -k chat -v                  # chat tests only
```

No Docker, no MQTT, no Ollama needed to run the tests — everything is
stubbed.

---

## Extending

### Adding a new tool

1. Add a function to `sentry/tools.py` decorated with `@tool`.
2. Add its schema to the `TOOLS` list in the same file.
3. The agent prompt (`system.j2`) will automatically include it.
4. Add a test case in `tests/test_smoke.py`.

### Swapping the LLM

1. Implement `sentry/llm/base.LLMClient` in a new file.
2. Update `sentry/__main__.py` to instantiate it instead of `OllamaClient`.
3. The `DecisionEngine` and `ChatService` are provider-agnostic — no other
   changes needed.

### Adding a sensor type

1. Add the new value to `SensorType` in `sentry/models.py` and mirror it
   in `sentryagent_app/lib/data/models/security_state.dart`.
2. Add classification rules in `sentry/event_classifier.py`.
3. The orchestrator and storage handle it automatically.
