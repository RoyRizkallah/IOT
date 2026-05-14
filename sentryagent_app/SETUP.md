# SentryAgent — Setup Guide

Get the app running on your machine in ~5 minutes.

## Prerequisites

You need:
- Flutter SDK (3.27 or later) — check with `flutter --version`
- Android Studio OR VS Code with the Flutter extension
- An Android emulator running, or a physical Android phone in USB debug mode

If `flutter doctor` shows red X's, fix those first. Don't proceed until it's all green checks (or only iOS missing — we don't need iOS).

## Step 1 — Install dependencies

The Flutter project shell has already been scaffolded. From this folder:

```bash
flutter pub get
```

This downloads `flutter_riverpod`, `google_fonts`, and `intl`. Should take ~30 seconds.

## Step 2 — Run

Plug in your phone (USB debugging on) or start an emulator, then:

```bash
flutter run
```

First build takes 1-2 minutes. After that, hot reload (press `r`) is instant.

## What you should see

**Splash:** pale background with the brand shield logo centered. A second later, the dashboard appears.

**Dashboard:**
- Top-left brand mark, top-right cyan ARMED pill
- A drifting blue/violet/cyan glow behind a large ring with "0" and "SECURE" in the middle
  - The ring has a slow scan-line sweeping clockwise (the system's heartbeat)
  - On threat-level change the ring fires a brief halo pulse + a haptic
- 2×2 grid of sensor tiles below: Motion (cyan), Sound (violet), Door (emerald), Temperature (coral)
  - Each tile has a colored top stripe and a pulsing dot when active
  - **Tap a tile → it Hero-flies into the Live Feed**
- "Live feed →" link in the section header takes you to the same screen
- Three quick-action cards: Test siren / Ask agent / View history (each one scales down on press + fires a tactile haptic)
- An ARM card with a Disarm/Arm button (medium haptic on press)

**Live Feed:**
- 1m / 5m / 10m window picker
- Sound waveform (smoothed area), temperature line chart, motion histogram, door state strip
- Charts populate from the rolling buffer as samples arrive

**Reasoning:** three pre-seeded agent decisions; tap any → severity pill flies via Hero into the detail screen, full context + reasoning + tool calls

**History:** chronological events, search, filter chips

**Agent:** chat with suggestion chips; the send button fires a haptic and the agent replies after a typing-dots animation

**Settings:** toggles, sliders, system info, privacy posture block

Every action that matters is reinforced with a haptic — tab change (light), button press (medium), test siren / level transition to alert (heavy).

## Troubleshooting

**`flutter pub get` fails:** Check your Flutter SDK version with `flutter --version`. If it's below 3.27, run `flutter upgrade`.

**Build fails with "Gradle" errors:** Open the `android/` folder in Android Studio once, let it index, then close it. Flutter sometimes needs Android Studio to seed the Gradle cache.

**Emulator very slow:** Use a real device. Emulators on low-RAM machines are painful.

**Fonts look like the system default:** Plus Jakarta Sans is downloaded on first run from Google Fonts; needs internet on first launch. After that, fonts are cached locally.

## When it works

Don't add features yet. Read the code top-down:

1. `lib/main.dart` — entry point
2. `lib/core/theme/` — colors, spacing, shadows, theme
3. `lib/core/providers.dart` — Riverpod glue (the swap point for MQTT later)
4. `lib/core/haptics.dart` + `lib/core/transitions.dart` — feel-of-the-app primitives
5. `lib/core/widgets/` — `SoftCard`, `PressScale`, `SeverityPill`, `SensorIconChip`
6. `lib/data/models/security_state.dart` — the domain
7. `lib/data/sources/mock_data_source.dart` — how the fake data is generated
8. `lib/features/shell/main_shell.dart` — the bottom nav
9. `lib/features/dashboard/` — Dashboard + ThreatRing + SensorTile + HeroBackdrop
10. `lib/features/live_feed/live_feed_screen.dart` — fl_chart-powered rolling buffers
11. `lib/features/reasoning/` — Reasoning Log + Decision Detail
12. `lib/features/history/history_screen.dart`
13. `lib/features/agent_console/agent_console_screen.dart`
14. `lib/features/settings/settings_screen.dart`

Android assets:

15. `android/app/src/main/res/drawable/ic_launcher_*.xml` — adaptive launcher icon (vector)
16. `android/app/src/main/res/drawable/launch_background.xml` — splash screen (background + centered shield)
17. `android/app/src/main/res/drawable/splash_logo.xml` — the splash shield vector

If a line confuses you, ask. You need to be able to defend every line in your viva.
