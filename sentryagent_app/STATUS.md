# SentryAgent — Project Status

Last updated: May 2026 — MQTT + SQLite + LLM integration complete.

For the full technical breakdown see `MOBILE_DOCS.md` (mobile) and
`sentry_agent/BACKEND_DOCS.md` (backend).

---

## Mobile App (Flutter) — Complete

### Foundation
- ✅ Flutter 3 project, Android branding (adaptive icon, splash screen)
- ✅ Light, premium design system — white surfaces, blue accent, threat halos
- ✅ Color tokens, spacing scale, shadow presets, Material 3 theme
- ✅ Plus Jakarta Sans (UI) + JetBrains Mono (data values) via google_fonts
- ✅ Riverpod state management — single `providers.dart`, StreamProviders for all live data
- ✅ Domain models: `SensorReading`, `SecurityEvent`, `AgentDecision`, `ChatMessage`, `SecurityState`

### Data Layer
- ✅ `SecurityDataSource` abstract interface with `ConnectionStatus` enum
- ✅ `MqttDataSource` — live MQTT implementation, auto-reconnect, no mock data
- ✅ `BrokerConfig` — host/port persisted via `SharedPreferences`
- ✅ History replay on (re)connect: publishes to `home/control/replay`,
     receives full state + event + decision + chat history from backend

### Screens
- ✅ **MainShell** — floating-pill bottom nav, animated active state, haptic on tab change
- ✅ **Dashboard** — animated threat ring, live sensor tiles, ConnectionPill, quick actions, arm card
- ✅ **Live Feed** — rolling-buffer charts (sound waveform, temperature line,
     motion histogram, door state strip) via fl_chart, 1m/5m/10m window picker
- ✅ **Alert History** — searchable, filterable event log (All / Today / Week / Critical)
- ✅ **Reasoning Log** — AgentDecision cards, Hero animation → Decision Detail
     (context, reasoning, tool calls, final action + reason)
- ✅ **Agent Console** — real-time chat with LLM agent over MQTT,
     typing indicator active until reply arrives, suggestion chips
- ✅ **Settings** — broker host/port edit, reconnect button, live connection status

### App-wide Polish
- ✅ `PressScale` widget — tactile scale-down + haptic on every tap target
- ✅ `FadeUpRoute` — fade + vertical lift navigation transition
- ✅ Five-level haptic vocabulary (tap / select / confirm / warning / alert)
- ✅ Custom launcher icon + splash screen

---

## Backend (Python + LLM) — Complete

- ✅ MQTT orchestrator (aiomqtt) — events, state, decisions, chat, replay
- ✅ Rule-based event classifier — fast pre-filter, no LLM for boring readings
- ✅ Local LLM agent — Qwen 2.5 7B via Ollama, Jinja2 prompts, 6 tools
- ✅ Chat service — separate async queue, never blocks security decisions
- ✅ SQLite persistence (aiosqlite, WAL) — events, decisions, chat, state
- ✅ Startup hydration — reloads last 50 rows from DB on restart
- ✅ Mock sensor publisher — default / suspicious / flapping scenarios
- ✅ Docker Compose — broker + sensors + agent + ollama-init auto-pull
- ✅ 74 passing tests, ruff clean

---

## What Is Not Yet Built

- ⬜ Raspberry Pi sensor reader (`pi.py`) — GPIO reads for real hardware
- ⬜ Push notifications (Firebase Cloud Messaging)
- ⬜ Biometric unlock to disarm (`local_auth`)
- ⬜ iOS app icon / splash (Android done)
- ⬜ MQTT authentication (currently anonymous — fine on a home LAN)

---

## What "Done" Looks Like

1. Open the app on a phone — dashboard shows live data from the backend
2. Trigger a sensor (mock scenario or real Pi) — dashboard updates in real time
3. Watch the agent reason in the Reasoning Log — full context, tools called, decision
4. Open the Agent Console and ask "what happened in the last hour?" — LLM answers
5. Restart the backend — app replays full history from SQLite on reconnect
6. *(Pi phase)* Trigger a real sensor — full loop closes without code changes
