@echo off
if "%OPENAI_API_KEY%"=="" (
  echo [pm2-setup] ERROR: OPENAI_API_KEY not set.
  exit /b 1
)
pm2 start ecosystem.config.cjs
pm2 logs unity-gateway --lines 10
