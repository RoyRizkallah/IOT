# SentryAgent — Mobile App

Flutter application for the SentryAgent IoT home security system.
Connects to the Python backend over MQTT, shows live sensor data,
agent reasoning, chat history, and sensor charts — zero mock data,
zero cloud dependency.

## Read these in order

1. **`MOBILE_DOCS.md`** — full technical documentation: architecture,
   providers, models, MQTT topics, screens, how to run
2. **`SentryAgent_Project_Proposal.docx`** — the original project concept

## What's in this package

```
sentryagent_app/
├── MOBILE_DOCS.md                         ← full technical documentation
├── pubspec.yaml                           ← Flutter dependencies
├── android/                               ← native Android shell
└── lib/
    ├── main.dart                          ← entry point, loads broker config
    ├── core/
    │   ├── providers.dart                 ← all Riverpod providers
    │   ├── format.dart                    ← time helpers
    │   ├── haptics.dart                   ← five-level haptic vocabulary
    │   ├── transitions.dart               ← FadeUpRoute navigation
    │   ├── theme/                         ← color tokens, spacing, shadows, theme
    │   └── widgets/                       ← ConnectionPill, SoftCard, SeverityPill…
    ├── data/
    │   ├── broker_config.dart             ← host/port, persisted via SharedPreferences
    │   ├── models/security_state.dart     ← Dart domain models (mirrors Python)
    │   └── sources/
    │       ├── security_data_source.dart  ← abstract interface + ConnectionStatus
    │       └── mqtt_data_source.dart      ← live MQTT implementation
    └── features/
        ├── shell/main_shell.dart          ← floating-pill bottom nav
        ├── dashboard/                     ← threat ring, sensor tiles, quick actions
        ├── live_feed/                     ← fl_chart: waveform, temp, motion, door
        ├── history/                       ← searchable, filterable event log
        ├── reasoning/                     ← agent decisions with full reasoning
        ├── agent_console/                 ← real-time chat with the LLM agent
        └── settings/                     ← broker config, reconnect, toggles
```

## Quick start

```bash
# 1. Start the backend first (see sentry_agent/README.md)
cd sentry_agent
docker compose --profile with-ollama up --build

# 2. In a separate terminal, run the Flutter app
cd sentryagent_app
flutter pub get
flutter run
```

The ConnectionPill in the top-right corner of the dashboard will turn
green (`LIVE`) once the MQTT connection is established.

## Connecting to the backend

| Device | Broker host to enter in Settings |
|---|---|
| Android emulator | `10.0.2.2` (default) |
| Physical device (same Wi-Fi) | LAN IP of the host machine, e.g. `192.168.1.5` |
| iOS simulator | `127.0.0.1` |

Open **Settings → Broker → Edit** in the app to change the host, then
tap **Reconnect**.
