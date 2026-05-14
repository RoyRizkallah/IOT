# SentryAgent - one-command demo bringup (Windows / PowerShell).
#
# What this does:
#   1. Verifies Docker Desktop is running.
#   2. Detects whether you have native Ollama running on :11434.
#        - If yes: reuses it (faster, GPU passthrough).
#        - If no:  brings up a containerised Ollama and pulls the model.
#   3. Starts the broker, mock sensors, and agent containers.
#   4. Prints a status summary and the next command to run for Flutter.
#
# Usage:
#   .\start.ps1                 # default flow
#   .\start.ps1 -Model llama3   # pick a different Ollama model
#   .\start.ps1 -SkipOllama     # do not touch Ollama (sensor-only smoke test)
#   .\start.ps1 -LaunchApp      # also run `flutter run` after the stack is up
#
# Tear down with: .\stop.ps1

[CmdletBinding()]
param(
    [string]$Model = "qwen2.5:7b-instruct",
    [switch]$SkipOllama,
    [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"
$BackendDir = Join-Path $PSScriptRoot "sentry_agent"
$AppDir = Join-Path $PSScriptRoot "sentryagent_app"

# --- Utilities --------------------------------------------------------------

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "[$Step] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Ok {
    param([string]$Message)
    Write-Host "      [ok] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "      [warn] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "      [err] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Test-Tcp {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 800)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok) { $client.EndConnect($iar) | Out-Null; $client.Close(); return $true }
        $client.Close(); return $false
    } catch { return $false }
}

function Wait-ContainerHealthy {
    param([string]$Container, [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $status = (docker inspect --format '{{.State.Health.Status}}' $Container 2>$null)
        if ($status -eq "healthy") { return $true }
        Start-Sleep -Milliseconds 800
    }
    return $false
}

# --- 1. Docker pre-flight ---------------------------------------------------

Write-Step "1/5" "Checking Docker Desktop..."
try {
    docker version --format '{{.Server.Version}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker version failed" }
    Write-Ok "Docker Desktop is running"
} catch {
    Write-Err "Docker is not reachable. Open Docker Desktop and try again."
    exit 1
}

# --- 2. Ollama strategy -----------------------------------------------------

Write-Step "2/5" "Detecting Ollama..."
$useNative = $false
if ($SkipOllama) {
    Write-Warn "SkipOllama set - agent will fail when it tries to reason. Demo only the sensor flow."
} elseif (Test-Tcp -HostName "localhost" -Port 11434) {
    $useNative = $true
    Write-Ok "Native Ollama is running on :11434 - reusing it"
} else {
    Write-Ok "No native Ollama - will start a containerised one"
}

# --- 3. Bring up the stack --------------------------------------------------
# Docker writes build progress to stderr; we route it through 2>&1 so
# PowerShell's "Stop" preference does not abort on what is just informational.

Write-Step "3/5" "Starting broker + sensors + agent..."
Push-Location $BackendDir
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    if ($useNative -or $SkipOllama) {
        & docker compose up -d --build broker sensors agent 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    } else {
        $env:SENTRY_OLLAMA_BASE_URL = "http://ollama:11434"
        & docker compose --profile with-ollama up -d --build broker sensors agent ollama 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "docker compose up failed (exit $LASTEXITCODE)"
        $ErrorActionPreference = $prevPref
        Pop-Location
        exit 1
    }
    Write-Ok "Containers started"
} finally {
    $ErrorActionPreference = $prevPref
    Pop-Location
}

# --- 4. Wait for broker + Ollama, pull model --------------------------------

Write-Step "4/5" "Waiting for services..."

if (-not (Wait-ContainerHealthy -Container "sentry-broker" -TimeoutSec 60)) {
    Write-Err "Broker did not reach healthy in time. Check: docker logs sentry-broker"
    exit 1
}
Write-Ok "Broker is healthy"

if (-not $SkipOllama) {
    if ($useNative) {
        Write-Host "      pulling model $Model on host..." -ForegroundColor DarkGray
        & ollama pull $Model
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "ollama pull returned non-zero - model may already exist or daemon unreachable"
        } else {
            Write-Ok "Model $Model ready (host Ollama)"
        }
    } else {
        if (-not (Wait-ContainerHealthy -Container "sentry-ollama" -TimeoutSec 60)) {
            Write-Err "Containerised Ollama did not come up. Check: docker logs sentry-ollama"
            exit 1
        }
        Write-Ok "Containerised Ollama is healthy"
        Write-Host "      pulling model $Model into the container (one-time, several GB)..." -ForegroundColor DarkGray
        docker exec sentry-ollama ollama pull $Model
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to pull $Model into sentry-ollama"
            exit 1
        }
        Write-Ok "Model $Model ready (containerised Ollama)"
    }
}

# --- 5. Summary -------------------------------------------------------------

Write-Step "5/5" "Live summary"
Write-Host ""
Write-Host "  Broker      mqtt://localhost:1883  (ws://localhost:9001)" -ForegroundColor White
if (-not $SkipOllama) {
    if ($useNative) {
        Write-Host "  Ollama      http://localhost:11434  (host)" -ForegroundColor White
    } else {
        Write-Host "  Ollama      http://localhost:11434  (container: sentry-ollama)" -ForegroundColor White
    }
}
Write-Host "  Agent       sentry-agent  (logs: docker logs -f sentry-agent)" -ForegroundColor White
Write-Host "  Sensors     sentry-sensors  (mock publisher, default scenario)" -ForegroundColor White
Write-Host ""
Write-Host "  Tail the bus traffic:" -ForegroundColor DarkGray
Write-Host "    docker compose -f sentry_agent/docker-compose.yml run --rm tools" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Watch the agent reason:" -ForegroundColor DarkGray
Write-Host "    docker logs -f sentry-agent" -ForegroundColor DarkGray
Write-Host ""

# --- Optional Flutter launch ------------------------------------------------

if ($LaunchApp) {
    Write-Host "Launching Flutter app..." -ForegroundColor Cyan
    if (-not (Test-Path $AppDir)) {
        Write-Err "Flutter app dir not found: $AppDir"
        exit 1
    }
    Push-Location $AppDir
    try {
        flutter pub get
        flutter run
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Next: launch the app" -ForegroundColor Cyan
    Write-Host "  cd sentryagent_app" -ForegroundColor White
    Write-Host "  flutter run" -ForegroundColor White
    Write-Host ""
    Write-Host "If you are on a real device (not the emulator), open the in-app Settings" -ForegroundColor DarkGray
    Write-Host "and set the broker host to your laptop LAN IP (e.g. 192.168.x.x)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Tear down with: .\stop.ps1" -ForegroundColor DarkGray
