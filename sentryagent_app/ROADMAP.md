# SentryAgent — Roadmap

Concrete tasks in the order they should be done. Don't skip ahead.

---

## Phase 0 — Prove the skeleton works (today)

**Goal:** Run the app, understand the code, change something small.

- [ ] Get the app running on a real device or emulator (see SETUP.md)
- [ ] Read every file in `lib/`. Note any line you don't understand.
- [ ] Change one color in `app_colors.dart` (e.g. swap accent cyan for orange). Hot reload. See it change. This proves you understand the design system.
- [ ] Change the mock data source to emit motion events more often. See the dashboard react.

**Don't move on until done.** Without this, everything else is wasted time.

---

## Phase 1 — Mobile app, all screens, mock data (Week 1-2)

Everything still uses `MockDataSource`. No backend yet. No hardware.

### Task 1.1 — Add navigation
- [ ] Create a `MainShell` widget with a bottom nav bar (4 tabs)
- [ ] Move `DashboardScreen` to be tab 1
- [ ] Add 3 placeholder screens for the other tabs (just a centered Text widget)
- [ ] Tabs: Dashboard, History, Agent, Settings

### Task 1.2 — Domain models for agent decisions and events
- [ ] Add `AgentDecision` class (id, timestamp, context, reasoning, toolsCalled, finalAction)
- [ ] Add `SecurityEvent` class (already partially in SensorReading — formalize it)
- [ ] Extend `MockDataSource` to emit a list of fake `AgentDecision`s

### Task 1.3 — Reasoning Log screen
- [ ] List of agent decisions, newest first
- [ ] Each card shows: timestamp, severity badge, one-line summary
- [ ] Tap a card → detail view with full reasoning text and tool calls

### Task 1.4 — Alert History screen
- [ ] Chronological list of all sensor events
- [ ] Filter chips: All / Today / Week / Critical-only
- [ ] Search bar (filters by sensor type)

### Task 1.5 — Agent Console (chat) screen
- [ ] Chat-style UI: user messages on right, agent on left
- [ ] Hardcode 3-4 example exchanges in mock data so it looks real
- [ ] Input field at bottom (won't actually send to LLM yet)

### Task 1.6 — Settings screen
- [ ] Toggles: Notifications enabled, Auto-arm at night
- [ ] Sliders: Agent confirmation timeout (30s, 60s, 90s)
- [ ] Static info: System status, App version

### Task 1.7 — Polish pass
- [ ] Add `google_fonts` package
- [ ] Pick fonts (suggestion: Geist Sans for UI, JetBrains Mono for numbers)
- [ ] Audit every padding for consistency
- [ ] Check dark mode on actual device under different lighting
- [ ] Add subtle animations (page transitions, tile pulse on activity)

---

## Phase 2 — MQTT, no real Pi yet (Week 3)

Run Mosquitto on your laptop. Replace `MockDataSource` with `MqttDataSource`. Write a Python script that publishes fake sensor data to the broker. The app now talks to "the real backend" — except the backend is a Python script on your laptop.

### Task 2.1 — Install Mosquitto
- [ ] Install Mosquitto MQTT broker on your laptop
- [ ] Verify it works with `mosquitto_pub` and `mosquitto_sub` from the terminal

### Task 2.2 — Python fake publisher
- [ ] Write `fake_publisher.py` that publishes random sensor readings to MQTT topics
- [ ] Topics: `home/security/motion`, `home/security/sound`, `home/security/door`, `home/security/temperature`
- [ ] Same JSON schema the real `sensor_reader.py` will use later

### Task 2.3 — Flutter MqttDataSource
- [ ] Add `mqtt_client` to pubspec.yaml
- [ ] Create `MqttDataSource implements SecurityDataSource`
- [ ] Subscribe to all 4 topics, build `SecurityState` from incoming messages
- [ ] Change ONE line in `dashboard_providers.dart` to use `MqttDataSource` instead of mock
- [ ] Verify the app still works exactly the same

This is the magic moment: nothing in the UI changes, but you've replaced the data source.

---

## Phase 3 — Backend on Pi (Week 4)

Real hardware. Real sensors. The Pi takes over from the fake publisher.

### Task 3.1 — Pi setup
- [ ] Flash Raspberry Pi OS (Lite, headless)
- [ ] SSH in, install Python 3, pip, paho-mqtt
- [ ] Wire up sensors per your hardware spec

### Task 3.2 — sensor_reader.py
- [ ] Read PIR via GPIO
- [ ] Read DHT11 via Adafruit_DHT or rpi-dht-sensor
- [ ] Read sound sensor via ADC (Grove Base HAT or MCP3008)
- [ ] Read reed switch via GPIO

### Task 3.3 — mqtt_client.py
- [ ] Publish each reading to its topic
- [ ] Use the same JSON schema as the fake publisher

### Task 3.4 — threat_scorer.py
- [ ] Implement weighted scoring (motion +3, sound +2, door +2, temp +1)
- [ ] Apply night-time multiplier (1.5x between 11pm-6am)
- [ ] Compute rolling sound baseline (24-hour average)
- [ ] Emit ThreatLevel based on score

### Task 3.5 — db_handler.py + SQLite schema
- [ ] Create tables: events, agent_decisions, user_responses
- [ ] Implement insert/query helpers

### Task 3.6 — main.py
- [ ] Wire everything: read sensors → score → log to DB → publish via MQTT
- [ ] Run as a systemd service so it starts on boot

---

## Phase 4 — Agent + LLM (Week 5)

The intelligent layer.

### Task 4.1 — Anthropic API key + first call
- [ ] Get an API key
- [ ] Write a smoke test: send "hello" to Claude, get a response, in Python

### Task 4.2 — agent_tools.py
- [ ] Define tools as Python functions with type hints and docstrings
- [ ] Tools: query_recent_events, get_arming_status, send_app_notification, request_user_confirmation, trigger_siren, log_decision

### Task 4.3 — agent_engine.py
- [ ] Build the system prompt (role, available tools, output schema)
- [ ] On YELLOW-zone events, call Claude with full context
- [ ] Parse tool calls from the response, execute them, log everything

### Task 4.4 — Conversational queries
- [ ] When the app sends a chat message via MQTT, route to the agent
- [ ] Agent answers using `query_recent_events` etc.
- [ ] Send answer back via MQTT to the app

---

## Phase 5 — Push notifications (Week 6)

### Task 5.1 — Firebase project
- [ ] Create Firebase project, add Android app
- [ ] Download `google-services.json`, drop into `android/app/`
- [ ] Add `firebase_messaging` to pubspec.yaml

### Task 5.2 — fcm_notifier.py on the Pi
- [ ] Use `firebase-admin` Python package
- [ ] Send notifications on RED-zone alerts
- [ ] Send confirmation requests on YELLOW-zone events

### Task 5.3 — Handle incoming notifications in Flutter
- [ ] Foreground: in-app banner
- [ ] Background: system notification with action buttons
- [ ] Action buttons send response back to Pi via MQTT

---

## Phase 6 — Demo prep (Week 7-8)

- [ ] Run the system continuously for 48 hours, fix everything that breaks
- [ ] Record a backup demo video (in case live demo fails)
- [ ] Write the report
- [ ] Practice the viva — every line of code, every design decision
- [ ] Prepare answers for: "Where's the AI?", "Why an LLM?", "What if internet drops?", "Privacy concerns?"

---

## What NOT to do

- Don't start Phase 2 before Phase 1 is fully done
- Don't buy hardware until Phase 2 works (proves your architecture is sound)
- Don't skip the polish pass — graders notice inconsistent padding more than they notice missing features
- Don't try to "get ahead" by building the Pi side before the app — you'll redesign half of it
