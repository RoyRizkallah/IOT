# SentryAgent

AI-powered home security system. Raspberry Pi + Flutter + Claude API.

## Read these in order

1. **`SentryAgent_Project_Proposal.docx`** — the project concept, what you're building and why
2. **`STATUS.md`** — exactly what's built, mocked, and missing right now
3. **`SETUP.md`** — get the app running on your machine in ~5 minutes
4. **`ROADMAP.md`** — concrete tasks for the rest of the project, in order

## What's in this package

```
sentryagent_app/
├── README.md                              ← you are here
├── STATUS.md                              ← what's done, what's not
├── SETUP.md                               ← how to run the app
├── ROADMAP.md                             ← what to build next
├── SentryAgent_Project_Proposal.docx      ← the proposal document
├── pubspec.yaml                           ← Flutter dependencies
├── android/                               ← native Android shell (generated)
└── lib/
    ├── main.dart                          ← app entry point
    ├── core/
    │   ├── providers.dart                 ← Riverpod glue + data-source seam
    │   ├── format.dart                    ← relative/absolute time helpers
    │   ├── theme/
    │   │   ├── app_colors.dart
    │   │   ├── app_spacing.dart
    │   │   ├── app_shadows.dart
    │   │   └── app_theme.dart
    │   └── widgets/
    │       ├── soft_card.dart
    │       ├── severity_pill.dart
    │       └── sensor_meta.dart
    ├── data/
    │   ├── models/security_state.dart     ← domain models
    │   └── sources/mock_data_source.dart  ← fake data for development
    └── features/
        ├── shell/main_shell.dart          ← floating-pill bottom nav
        ├── dashboard/
        │   ├── dashboard_screen.dart
        │   └── widgets/
        │       ├── hero_backdrop.dart
        │       ├── threat_ring.dart
        │       └── sensor_tile.dart
        ├── reasoning/
        │   ├── reasoning_log_screen.dart
        │   └── decision_detail_screen.dart
        ├── history/history_screen.dart
        ├── agent_console/agent_console_screen.dart
        └── settings/settings_screen.dart
```

## Right now

You should:
1. Read `STATUS.md` so you know what state the project is in
2. Open `SETUP.md` and run the app
3. When the dashboard is animating on your screen, come back and ask for the next phase

Don't read more code or ask for more files until the current code runs on your machine and you understand what it does.
