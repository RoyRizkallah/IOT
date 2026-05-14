# SentryAgent — Project Status

Last updated: post-polish + live-feed pass.

## Legend
- ✅ Built and working
- 🟡 Stubbed / mocked (works in app, not real)
- ⬜ Not built yet

---

## Mobile App (Flutter)

### Foundation
- ✅ Real Flutter project scaffold (`android/`, `.metadata`, etc.)
- ✅ Light, premium design system (white surfaces, blue accent, threat halos)
- ✅ Color tokens (`app_colors.dart`)
- ✅ Spacing + radius scale (`app_spacing.dart`)
- ✅ Layered shadow tokens (`app_shadows.dart`)
- ✅ Material 3 light theme with Plus Jakarta Sans + JetBrains Mono via `google_fonts`
- ✅ Riverpod state management wired up (one provider file: `core/providers.dart`)
- ✅ Domain models: `SensorType`, `ThreatLevel`, `SecurityState`, `SensorReading`,
      `SecurityEvent`, `AgentDecision`, `AgentToolCall`, `ChatMessage`
- ✅ `SecurityDataSource` abstract interface
- 🟡 `MockDataSource` — emits sensor state, events, decisions, chat (replaced by MQTT in Phase 2)

### Polish primitives (new)
- ✅ `core/haptics.dart` — five-level haptic vocabulary (tap / select / confirm / warning / alert)
- ✅ `core/transitions.dart` — `FadeUpRoute` (fade + subtle vertical lift) used for in-app navigation
- ✅ `core/widgets/press_scale.dart` — tactile scale-down + haptic on every primary tap target
- ✅ `core/widgets/soft_card.dart` — canonical white card with layered shadow
- ✅ `core/widgets/severity_pill.dart` — pastel-backed threat-level badge (Hero-shared)
- ✅ `core/widgets/sensor_meta.dart` — per-sensor icon + colour helpers
- ✅ `core/format.dart` — relative + absolute time formatters

### Screens
- ✅ **MainShell** — floating-pill bottom nav, animated active state, haptic on tab change
- ✅ **Home Dashboard** — animated multi-blob gradient backdrop, threat ring with scan-line +
      level-change halo pulse + medium/heavy haptic, premium sensor tiles with active-state halo,
      tap a tile → Hero-flies into Live Feed, three Quick Actions with press-scale + haptic,
      arm card with confirm haptic
- ✅ **Reasoning Log** — list of `AgentDecision` cards with severity pill, tool chips; tap →
      Hero animation on the severity pill, fade-up route into the full Decision Detail
- ✅ **Decision Detail** — context, reasoning, tool calls, final action; severity pill is the
      Hero target from the list
- ✅ **Alert History** — chronological event list, search, filter chips (All / Today / Week / Critical)
- ✅ **Agent Console** — chat UI, animated typing indicator, suggestion chips, send haptic, mock round-trip
- ✅ **Live Feed** *(new)* — rolling-buffer charts via `fl_chart`:
      - Sound: smoothed area chart (the "waveform")
      - Temperature: line chart with end-cap dot
      - Motion: 12-bucket histogram of detections in the window
      - Door: open/closed state-strip painted with `CustomPainter`
      - Window picker (1m / 5m / 10m), animated live indicator
- ✅ **Settings** — notifications toggle, auto-arm, confirm-yellow toggle, timeout slider,
      system info, privacy posture block

### App-wide
- ✅ Bottom navigation between screens
- ✅ Custom fonts (Plus Jakarta Sans + JetBrains Mono)
- ✅ Subtle motion on every screen (gradient drift, ring scan, tile pulse, typing dots, ring level pulse)
- ✅ Adaptive launcher icon (vector drawable: blue→cyan gradient background, white shield foreground,
      cyan accent dot, monochrome variant for Android 13+ themed icons)
- ✅ Splash screen (pale `bgBase` background with the brand shield logo centered)
- ⬜ Push notifications (Firebase Cloud Messaging)
- ⬜ Real `MqttDataSource`
- ⬜ REST API client for historical queries
- ⬜ Biometric to disarm (`local_auth`)

---

## Backend (Raspberry Pi — Python)

### Not started yet — building app first.

- ⬜ `sensor_reader.py` — reads PIR/sound/door/DHT11
- ⬜ `mqtt_client.py` — publishes sensor data, subscribes to control commands
- ⬜ `threat_scorer.py` — fast deterministic scoring (Layer 1)
- ⬜ `actuator.py` — controls siren, LEDs
- ⬜ `agent_engine.py` — calls Claude API, parses tool calls (Layer 2)
- ⬜ `agent_tools.py` — defines and executes the agent's toolset
- ⬜ `fcm_notifier.py` — sends push notifications to the app
- ⬜ `db_handler.py` — SQLite I/O
- ⬜ `serializer.py` — JSON serialization
- ⬜ `api_server.py` — Flask REST API
- ⬜ `main.py` — orchestrates everything

---

## Infrastructure

- ⬜ Mosquitto MQTT broker (install on laptop first, Pi later)
- ⬜ Firebase project + FCM setup
- ⬜ Anthropic API key (for the LLM agent)
- ⬜ SQLite schema (3 tables: events, agent_decisions, user_responses)

---

## Hardware

- ⬜ Raspberry Pi (any model, but Pi 4 with 4GB+ recommended)
- ⬜ Grove PIR Motion Sensor
- ⬜ DHT11 Temperature/Humidity Sensor
- ⬜ Grove Sound Sensor
- ⬜ Magnetic Reed Switch
- ⬜ Buzzer or active siren
- ⬜ Jumper wires + breadboard or Grove HAT

---

## What "done" looks like

A grader can:
1. Open the app on a phone, see the dashboard with live data from the real Pi
2. Trigger a sensor (e.g. open the door) and see the dashboard update in real time
3. Get a push notification when the threat level hits RED
4. Open the Agent Console and ask "what happened in the last hour?" — get a real LLM-generated answer
5. See the agent's reasoning logged with full transparency
6. Receive a YELLOW-zone confirmation ("is this you?") and respond from the app
