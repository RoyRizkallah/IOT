#!/usr/bin/env bash
# SentryAgent — one-command demo bringup (Linux / macOS).
#
# No fake data by default — the Raspberry Pi is the data source. Set MOCK=1 for
# a laptop-only run (adds the simulated sensor publisher).
#
# Usage:
#   ./start.sh                    # real-Pi stack (broker + agent + camera)
#   MOCK=1 ./start.sh             # also start the simulated sensor publisher
#   MODEL=llama3 ./start.sh       # pick a different Ollama model
#   SKIP_OLLAMA=1 ./start.sh      # don't touch Ollama
#   LAUNCH_APP=1 ./start.sh       # also `flutter run` after the stack is up

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/sentry_agent"
APP_DIR="$SCRIPT_DIR/sentryagent_app"
MODEL="${MODEL:-qwen2.5:7b-instruct}"
SKIP_OLLAMA="${SKIP_OLLAMA:-}"
MOCK="${MOCK:-}"
LAUNCH_APP="${LAUNCH_APP:-}"

cyan()   { printf "\033[36m%s\033[0m" "$1"; }
green()  { printf "\033[32m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
red()    { printf "\033[31m%s\033[0m" "$1"; }

step() { printf "%s %s\n" "$(cyan "[$1]")" "$2"; }
ok()   { printf "      %s %s\n" "$(green "[ok]")"  "$1"; }
warn() { printf "      %s %s\n" "$(yellow "[warn]")" "$1"; }
err()  { printf "      %s %s\n" "$(red "[err]")"  "$1"; }

tcp_ok() {
    (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null && exec 3>&- 3<&- && return 0 || return 1
}

wait_healthy() {
    local container="$1" timeout="${2:-60}" deadline
    deadline=$(( $(date +%s) + timeout ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if [ "$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null)" = "healthy" ]; then
            return 0
        fi
        sleep 0.8
    done
    return 1
}

# ─── 1. Docker pre-flight ───────────────────────────────────────────────────
step "1/5" "Checking Docker..."
if ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
    err "Docker isn't reachable. Start it and try again."
    exit 1
fi
ok "Docker is running"

# ─── 2. Ollama strategy ─────────────────────────────────────────────────────
step "2/5" "Detecting Ollama..."
USE_NATIVE=0
if [ -n "$SKIP_OLLAMA" ]; then
    warn "SKIP_OLLAMA set — agent will fail when it tries to reason."
elif tcp_ok localhost 11434; then
    USE_NATIVE=1
    ok "Native Ollama on :11434 — reusing it"
else
    ok "No native Ollama — will start a containerised one"
fi

# ─── 3. Bring up the stack ──────────────────────────────────────────────────
cd "$BACKEND_DIR"
SERVICES=(broker agent camera)
COMPOSE_ARGS=()
if [ -n "$MOCK" ]; then
    SERVICES+=(sensors)
    COMPOSE_ARGS+=(--profile mock)
    step "3/5" "Starting broker + agent + camera + mock sensors..."
else
    step "3/5" "Starting broker + agent + camera..."
fi
if [ "$USE_NATIVE" = "1" ] || [ -n "$SKIP_OLLAMA" ]; then
    docker compose "${COMPOSE_ARGS[@]+"${COMPOSE_ARGS[@]}"}" up -d --build "${SERVICES[@]}"
else
    SERVICES+=(ollama)
    SENTRY_OLLAMA_BASE_URL="http://ollama:11434" \
        docker compose "${COMPOSE_ARGS[@]+"${COMPOSE_ARGS[@]}"}" --profile with-ollama up -d --build "${SERVICES[@]}"
fi
ok "Containers started"

# ─── 4. Wait for broker + Ollama, pull model ────────────────────────────────
step "4/5" "Waiting for services..."
if ! wait_healthy sentry-broker 60; then
    err "Broker not healthy. Check: docker logs sentry-broker"
    exit 1
fi
ok "Broker is healthy"

if [ -z "$SKIP_OLLAMA" ]; then
    if [ "$USE_NATIVE" = "1" ]; then
        echo "      pulling model $MODEL on host..."
        ollama pull "$MODEL" || warn "ollama pull non-zero — model may already exist"
        ok "Model $MODEL ready (host Ollama)"
    else
        if ! wait_healthy sentry-ollama 60; then
            err "Containerised Ollama not healthy. Check: docker logs sentry-ollama"
            exit 1
        fi
        ok "Containerised Ollama is healthy"
        echo "      pulling model $MODEL into the container (one-time, ~4GB)..."
        docker exec sentry-ollama ollama pull "$MODEL"
        ok "Model $MODEL ready (containerised Ollama)"
    fi
fi

# ─── 5. Summary ─────────────────────────────────────────────────────────────
step "5/5" "Live summary"
echo ""
echo "  Broker      mqtt://localhost:1883  (ws://localhost:9001)"
if [ -z "$SKIP_OLLAMA" ]; then
    if [ "$USE_NATIVE" = "1" ]; then
        echo "  Ollama      http://localhost:11434  (host)"
    else
        echo "  Ollama      http://localhost:11434  (container: sentry-ollama)"
    fi
fi
echo "  Agent       sentry-agent  (logs: docker logs -f sentry-agent)"
echo "  Camera      sentry-camera  (relay on http://localhost:8000/)"
if [ -n "$MOCK" ]; then
    echo "  Sensors     sentry-sensors  (mock publisher)"
else
    echo "  Sensors     waiting for the Raspberry Pi on iot/pi/telemetry"
fi
echo ""
echo "  Tail the bus traffic:"
echo "    docker compose -f sentry_agent/docker-compose.yml run --rm tools"
echo ""

if [ -n "$LAUNCH_APP" ]; then
    cd "$APP_DIR"
    flutter pub get
    flutter run
else
    echo "Next: launch the app"
    echo "  cd sentryagent_app && flutter run"
    echo ""
    echo "On a real device, open Settings in the app and point the broker at your"
    echo "laptop's LAN IP (e.g. 192.168.x.x:1883)."
fi

echo ""
echo "Tear down with: ./stop.sh"
