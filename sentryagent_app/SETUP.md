# SentryAgent — Setup Guide

Get the full system running (backend + mobile app) in one shot.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | Latest | https://www.docker.com/products/docker-desktop |
| Flutter SDK | ≥ 3.27 | https://docs.flutter.dev/get-started/install |
| Android Studio / emulator | Any | For running the app |

---

## Step 1 — Start the backend

```powershell
cd sentry_agent

# Option A: No Ollama installed — fully containerised (first run pulls ~9 GB)
docker compose --profile with-ollama up --build

# Option B: Ollama already installed natively (faster, uses GPU)
ollama pull qwen2.5:7b-instruct
docker compose up --build
```

Wait until you see the agent print its startup banner:

```
╭─────────────────────────────╮
│   SentryAgent · serve       │
│  Broker  broker:1883        │
│  Ollama  http://...         │
│  Model   qwen2.5:7b-instruct│
│  DB      /data/sentry.db   │
╰─────────────────────────────╯
```

---

## Step 2 — Run the Flutter app

```bash
cd sentryagent_app
flutter pub get
flutter run
```

The first build takes 2–3 minutes (Gradle downloads). Subsequent runs are fast.

---

## Step 3 — Connect to the broker

The app defaults to `10.0.2.2:1883` which works for the **Android emulator**.

| Device | Broker host |
|---|---|
| Android emulator | `10.0.2.2` (default, no change needed) |
| Physical Android on Wi-Fi | LAN IP of your laptop, e.g. `192.168.1.5` |
| iOS simulator | `127.0.0.1` |

To change it: open **Settings → Broker → Edit** in the app, enter the host,
tap **Save**, then **Reconnect**.

The **ConnectionPill** in the top-right of the dashboard will turn green
(`LIVE`) when connected.

---

## Step 4 — Verify it's working

In a separate terminal, tail the MQTT bus to watch data flow:

```powershell
docker compose -f sentry_agent/docker-compose.yml run --rm tools \
  mosquitto_sub -h broker -t 'home/#' -v
```

You should see `home/sensors/*` readings and `home/agent/state` heartbeats
every 5 seconds. When the mock scenario generates a warning event, you'll
see `home/agent/decision` appear with the LLM's reasoning.

Check the SQLite database is being written:

```powershell
docker exec sentry-agent sqlite3 /data/sentry.db \
  "SELECT id, severity, message FROM events ORDER BY timestamp DESC LIMIT 5;"
```

---

## Tear down

```powershell
# Stop everything, keep data (DB + Ollama model cache)
docker compose --profile with-ollama down

# Stop everything AND wipe all data
docker compose --profile with-ollama down -v
```

---

## Troubleshooting

**App shows OFFLINE / NO BROKER**
- Confirm Docker containers are running: `docker ps`
- Check you're using the right broker host for your device type (see Step 3)
- Tap **Settings → Reconnect**

**First run takes forever**
- Ollama image (~4 GB) + model weights (~4.5 GB) download once and are cached.
  Subsequent starts are seconds.

**`flutter run` fails on Gradle**
- Stop any running Gradle daemons: `.\android\gradlew.bat --stop`
- Delete stale locks: `Get-ChildItem android\.gradle -Recurse -Filter *.lock | Remove-Item`
- Run `flutter run` again
