@echo off
setlocal
set "NODE_OPTIONS=--max-old-space-size=512"
if "%OPENAI_API_KEY%"=="" (
  echo [start-gateway] ERROR: OPENAI_API_KEY not set.
  exit /b 1
)
node server.cjs --model gpt-4o-realtime-preview --input-audio-format pcm16 --output-audio-format pcm16 --port 8765 --verbose
