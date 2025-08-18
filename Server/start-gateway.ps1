Param()

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $PSScriptRoot

if (-not $env:OPENAI_API_KEY) {
  Write-Error "Please set OPENAI_API_KEY first (e.g. `$env:OPENAI_API_KEY = 'sk-...' )"
  exit 1
}

if (-not (Test-Path "node_modules")) {
  Write-Host "[start-gateway] Installing dependencies..."
  npm install --silent
}

Write-Host "[start-gateway] Starting gateway on ws://127.0.0.1:8765 with model gpt-4o-realtime-preview"
node gateway.js --model gpt-4o-realtime-preview --port 8765 --min-commit-ms 120
