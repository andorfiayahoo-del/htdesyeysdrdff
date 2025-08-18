#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

if [ -z "$OPENAI_API_KEY" ]; then
  echo "Please export OPENAI_API_KEY first (e.g. export OPENAI_API_KEY=sk-...)" 1>&2
  exit 1
fi

# Install deps once
if [ ! -d "node_modules" ]; then
  echo "[start-gateway] Installing dependencies..."
  npm install --silent
fi

echo "[start-gateway] Starting gateway on ws://127.0.0.1:8765 with model gpt-4o-realtime-preview"
node gateway.js --model gpt-4o-realtime-preview --port 8765 --min-commit-ms 120
