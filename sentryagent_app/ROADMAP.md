# SentryAgent — Roadmap

## Completed

### Phase 1 — Mobile Foundation
- ✅ Flutter scaffold, design system, theme, navigation shell
- ✅ Domain models mirroring Python Pydantic models
- ✅ All 6 screens: Dashboard, Live Feed, History, Reasoning, Chat, Settings
- ✅ Polish: haptics, hero animations, press-scale, fade-up transitions
- ✅ Android adaptive icon + splash screen

### Phase 2 — Backend + Live Integration
- ✅ Python MQTT orchestrator with aiomqtt
- ✅ Rule-based event classifier (Layer 1)
- ✅ Local LLM decision engine — Ollama, Jinja2 prompts, 6 tool calls (Layer 2)
- ✅ Chat service with dedicated async queue
- ✅ SQLite persistence — events, decisions, chat, state (aiosqlite, WAL)
- ✅ Live `MqttDataSource` in Flutter — zero mock data
- ✅ History replay on reconnect
- ✅ Broker config persisted via `SharedPreferences`
- ✅ Docker Compose stack — one command, model auto-pull
- ✅ 74 passing tests

---

## Remaining

### Phase 3 — Raspberry Pi Hardware

**Backend** — one new file: `sentry/sensors/pi.py`
- Read GPIO: PIR motion sensor, magnetic reed switch (door),
  sound module, DHT22 temperature/humidity
- Publish to the same `home/sensors/<type>` topics mock currently uses
- Subscribe to `home/control/siren` → drive buzzer/LED
- No changes needed to the agent, database, or Flutter app

**Infrastructure**
- Pi OS setup + Python environment
- Point `SENTRY_MQTT_HOST` at the laptop's LAN IP
- `systemd` unit so `pi.py` autostarts on boot

### Phase 4 — Nice to Have (optional)
- Push notifications via Firebase Cloud Messaging
- Biometric unlock to disarm (`local_auth`)
- iOS app icon + splash
- MQTT username/password auth for non-home-LAN deployments
