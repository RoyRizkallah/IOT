#!/usr/bin/env bash
# SentryAgent — graceful teardown.
#
# Usage:
#   ./stop.sh              # stop containers, keep volumes
#   WIPE=1 ./stop.sh       # also remove volumes

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/sentry_agent"

echo "[stop] Tearing down SentryAgent stack..."
args=(--profile with-ollama --profile tools down)
if [ -n "${WIPE:-}" ]; then
    args+=(--volumes)
    echo "       (wiping volumes — Ollama model and broker history will be re-fetched)"
fi
docker compose "${args[@]}"

echo "[ok] All down."
