# SentryAgent — Mobile App Documentation

Flutter application for the SentryAgent IoT home security system.
Connects to the backend over MQTT, shows live sensor data, agent reasoning,
chat, and history — with no mock data and no cloud dependency.

---

## Tech Stack

| Layer | Library | Why |
|---|---|---|
| State management | `flutter_riverpod ^2.6.1` | Provider graph, `StreamProvider` for live MQTT streams |
| MQTT client | `mqtt_client ^10.5.0` | Connects to Mosquitto broker |
| Charts | `fl_chart ^0.69.2` | Sound waveform, temperature line, motion histogram |
| Typography | `google_fonts ^6.2.1` | Plus Jakarta Sans (UI) + JetBrains Mono (data values) |
| Persistence | `shared_preferences ^2.3.0` | Saves the broker host/port between app launches |
| Time formatting | `intl ^0.19.0` | Relative timestamps in history and reasoning log |

---

## Project Structure

```
lib/
├── main.dart                        # Entry point — loads broker config, mounts ProviderScope
├── core/
│   ├── providers.dart               # All Riverpod providers (single source of truth)
│   ├── format.dart                  # Relative + absolute time helpers
│   ├── haptics.dart                 # Five-level haptic vocabulary
│   ├── transitions.dart             # FadeUpRoute — shared navigation transition
│   ├── theme/
│   │   ├── app_colors.dart          # Color tokens (bgBase, accent, threat levels)
│   │   ├── app_shadows.dart         # Layered BoxShadow presets
│   │   ├── app_spacing.dart         # Spacing + radius scale
│   │   └── app_theme.dart           # Material 3 ThemeData
│   └── widgets/
│       ├── connection_pill.dart     # LIVE / CONNECTING / OFFLINE indicator
│       ├── press_scale.dart         # Tactile scale-down + haptic on tap
│       ├── soft_card.dart           # White card with layered shadow
│       ├── severity_pill.dart       # Pastel threat-level badge (Hero-shared)
│       └── sensor_meta.dart         # Per-sensor icon + colour helpers
├── data/
│   ├── broker_config.dart           # BrokerConfig + SharedPreferences load/save
│   ├── models/
│   │   └── security_state.dart      # Dart domain models — mirrors Python Pydantic models
│   └── sources/
│       ├── security_data_source.dart # Abstract interface + ConnectionStatus enum
│       └── mqtt_data_source.dart     # Concrete MQTT implementation
└── features/
    ├── shell/
    │   └── main_shell.dart          # Floating-pill bottom nav, tab routing
    ├── dashboard/
    │   ├── dashboard_screen.dart    # Threat ring, sensor tiles, quick actions
    │   └── widgets/                 # ThreatRing, SensorTile, ActivityStrip, SmartInsightChip…
    ├── live_feed/
    │   └── live_feed_screen.dart    # fl_chart: sound waveform, temp line, motion histogram, door strip
    ├── history/
    │   ├── history_screen.dart      # Searchable, filterable event log
    │   └── widgets/event_detail_sheet.dart
    ├── reasoning/
    │   ├── reasoning_log_screen.dart   # List of AgentDecisions
    │   └── decision_detail_screen.dart # Context, reasoning, tool calls, final action
    ├── agent_console/
    │   └── agent_console_screen.dart   # Real-time chat with the LLM agent
    └── settings/
        └── settings_screen.dart     # Broker config, reconnect, toggles
```

---

## Architecture

### Data Flow

```
Mosquitto broker (Docker)
        │
        │  MQTT over TCP (port 1883)
        ▼
MqttDataSource
   • Subscribes to home/agent/state, home/events, home/agent/decision,
     home/agent/chat/out, home/agent/replay
   • Publishes to home/control/arm, home/control/siren,
     home/control/chat/in, home/control/replay
   • Maintains StreamControllers for each topic
   • Auto-reconnects; emits ConnectionStatus updates
        │
        │  Dart Streams
        ▼
Riverpod providers  (core/providers.dart)
   securityStateProvider → Dashboard
   eventsProvider        → Alert History
   decisionsProvider     → Reasoning Log
   chatProvider          → Agent Console
   connectionStatusProvider → ConnectionPill + Settings
        │
        │  Widget.watch / Widget.listen
        ▼
UI screens
```

### State Management (Riverpod)

| Provider | Type | Consumers |
|---|---|---|
| `brokerConfigProvider` | `StateNotifier<BrokerConfig>` | Settings screen, `dataSourceProvider` |
| `dataSourceProvider` | `Provider<SecurityDataSource>` | Re-created on broker config change |
| `mqttDataSourceProvider` | `Provider<MqttDataSource>` | Settings "Reconnect" button |
| `securityStateProvider` | `StreamProvider<SecurityState>` | Dashboard, ConnectionPill |
| `eventsProvider` | `StreamProvider<List<SecurityEvent>>` | Alert History |
| `decisionsProvider` | `StreamProvider<List<AgentDecision>>` | Reasoning Log |
| `chatProvider` | `StreamProvider<List<ChatMessage>>` | Agent Console |
| `connectionStatusProvider` | `StreamProvider<ConnectionStatus>` | AppBar pill, Settings |
| `mainTabIndexProvider` | `StateProvider<int>` | MainShell, ConnectionPill tap |

---

## Domain Models

All models are in `lib/data/models/security_state.dart` and mirror the
Python Pydantic models **field-for-field** — JSON flows through MQTT unchanged.

### SensorReading
```dart
SensorReading {
  SensorType type;       // motion | sound | door | temperature
  double value;          // dB / °C / 0.0 or 1.0 for binary sensors
  bool active;
  DateTime timestamp;
}
```

### SecurityEvent
```dart
SecurityEvent {
  String id;
  SensorType sensor;
  ThreatLevel severity;  // safe | warning | alert
  String message;        // "Motion detected at the back door"
  DateTime timestamp;
  double? rawValue;
}
```

### AgentDecision
```dart
AgentDecision {
  String id;
  DateTime timestamp;
  ThreatLevel severity;
  String summary;            // one-line headline
  String context;            // what the agent saw
  String reasoning;          // why it decided what it did
  List<AgentToolCall> toolsCalled;
  String finalAction;        // ignore | log | notify_user | trigger_siren | …
  String finalActionReason;  // human-readable phrasing
}
```

### ChatMessage
```dart
ChatMessage {
  String id;
  ChatRole role;    // user | agent
  String text;
  DateTime timestamp;
  String? inReplyTo;  // id of the user message this answers
}
```

---

## MQTT Topics

| Topic | Direction | Payload |
|---|---|---|
| `home/agent/state` | broker → app | `SecurityState` JSON (retained, every ~5 s) |
| `home/events` | broker → app | `SecurityEvent` JSON |
| `home/agent/decision` | broker → app | `AgentDecision` JSON |
| `home/agent/chat/out` | broker → app | `ChatMessage` JSON (role: agent) |
| `home/agent/replay` | broker → app | `{state, events, decisions, chat}` bulk dump |
| `home/control/arm` | app → broker | `{"armed": true}` |
| `home/control/chat/in` | app → broker | `ChatMessage` JSON (role: user) |
| `home/control/replay` | app → broker | `{}` — "give me current world state" |
| `home/control/siren` | app → broker | `{"action": "trigger" \| "stop"}` |

On (re)connect the app publishes to `home/control/replay` immediately, so
the UI is populated from the agent's in-memory + SQLite history even if the
app was closed for hours.

---

## Key Screens

### Dashboard
- **ThreatRing** — animated ring whose color shifts green → amber → red with
  the current `threat_score`. Pulses on level change.
- **SensorTiles** — live readings for motion, sound, door, temperature.
  Active sensors show a colored halo.
- **ConnectionPill** — top-right corner. Tapping it navigates to Settings.
- **Quick Actions** — arm/disarm, siren, refresh. All with `PressScale` haptics.

### Alert History
- Searchable, filterable (`All / Today / This Week / Critical`) event log.
- Tap an event → `EventDetailSheet` bottom sheet.

### Reasoning Log
- List of `AgentDecision` cards. Tap → Hero animation on the severity pill
  into `DecisionDetailScreen` showing context, reasoning, tool calls.

### Agent Console
- Chat UI. Typing indicator stays active until the broker delivers the reply.
- "Send" button publishes a `ChatMessage` to `home/control/chat/in`.
- Agent reply arrives on `home/agent/chat/out`.

### Live Feed
- Rolling-buffer charts with a window picker (1m / 5m / 10m):
  - Sound: smoothed area chart
  - Temperature: line chart
  - Motion: 12-bucket histogram
  - Door: open/closed state-strip (`CustomPainter`)

### Settings
- Edit broker host + port → triggers `MqttDataSource.reconfigure()`.
- Changes are persisted to `SharedPreferences` automatically.
- "Reconnect" button for manual recovery.

---

## Running the App

### Prerequisites
- Flutter SDK ≥ 3.27
- Backend stack running (see `sentry_agent/README.md`)
- Android emulator or physical device

### Commands
```bash
cd sentryagent_app
flutter pub get
flutter run
```

### Connecting to the backend

| Target | Broker host in Settings |
|---|---|
| Android emulator | `10.0.2.2` (default) |
| Physical device on same Wi-Fi | LAN IP of the host machine (e.g. `192.168.1.5`) |
| iOS simulator | `127.0.0.1` |

Open **Settings → Broker** in the app to change the host, then tap **Reconnect**.
The ConnectionPill will turn green (`LIVE`) once the MQTT handshake completes.

---

## Android Branding

| Asset | Location |
|---|---|
| Adaptive icon (foreground) | `android/app/src/main/res/drawable/ic_launcher_foreground.xml` |
| Adaptive icon (background) | `android/app/src/main/res/drawable/ic_launcher_background.xml` |
| Splash screen logo | `android/app/src/main/res/drawable/splash_logo.xml` |
| Splash background color | `android/app/src/main/res/values/colors.xml` → `bgBase` |

---

## What Is Not Yet Built
- Push notifications (Firebase Cloud Messaging)
- Biometric unlock to disarm (`local_auth`)
- iOS app icon / splash (Android only for now)
