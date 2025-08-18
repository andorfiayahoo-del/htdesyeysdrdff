@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

echo :: ===== UNITY GATEWAY - CLEAN START & TAIL =====

REM Known-good defaults (change if needed)
set MODEL=gpt-4o-realtime-preview
set INPUT_AUDIO_FORMAT=pcm16
set OUTPUT_AUDIO_FORMAT=pcm16
REM Align this to your Unity player OutputRateHz (StreamingAudioPlayer default is 48000):
set OUTPUT_SAMPLE_RATE=48000
REM Unity mic is typically 44100, that’s fine; server will pass-through as pcm16.

REM Clean previous
pm2 stop   unity-gateway  2>NUL
pm2 delete unity-gateway  2>NUL
pm2 flush  unity-gateway  2>NUL

REM Start with fresh env
pm2 start server.cjs --name unity-gateway --update-env --time

REM Tail the logs
pm2 logs unity-gateway --lines 0
