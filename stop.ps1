# SentryAgent - graceful teardown.
#
# Stops every container started by start.ps1 and removes the network. Volumes
# (mosquitto data, ollama models) are kept by default so the next demo starts
# instantly. Use -Wipe to drop them too.
#
# Usage:
#   .\stop.ps1          # default: stop containers, keep volumes
#   .\stop.ps1 -Wipe    # also remove volumes (re-pulls Ollama model on next run)

[CmdletBinding()]
param([switch]$Wipe)

$ErrorActionPreference = "Stop"
$BackendDir = Join-Path $PSScriptRoot "sentry_agent"

Write-Host "[stop] Tearing down SentryAgent stack..." -ForegroundColor Cyan
Push-Location $BackendDir
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $cmdArgs = @("--profile", "with-ollama", "--profile", "tools", "down")
    if ($Wipe) {
        $cmdArgs += "--volumes"
        Write-Host "       (wiping volumes - Ollama model and broker history will be re-fetched)" -ForegroundColor Yellow
    }
    & docker compose @cmdArgs 2>&1 | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[err] docker compose down failed (exit $LASTEXITCODE)" -ForegroundColor Red
        $ErrorActionPreference = $prevPref
        Pop-Location
        exit 1
    }
} finally {
    $ErrorActionPreference = $prevPref
    Pop-Location
}

Write-Host "[ok] All down." -ForegroundColor Green
