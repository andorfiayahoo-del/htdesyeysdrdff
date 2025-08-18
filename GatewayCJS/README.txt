GatewayCJS-fixed
==================

What changed
------------
- **Fixed** `server.cjs` (your previous copy had `...` elisions which caused `SyntaxError: Unexpected token '.'`).
- **Forces** session.input_audio_format/output_audio_format to plain strings (`"pcm16"`), eliminating the `invalid_type` errors.
- **Auto-commits** mic audio only after at least one append (prevents `input_audio_buffer_commit_empty`).
- **Heartbeat pings** the upstream every 20s (prevents `keepalive ping timeout`).
- **Memory cap** via PM2 `--max-old-space-size=512` and no unbounded audio queues.

Quick start
-----------
1) Open a terminal in this folder and install deps:

    npm i

2) Set your OpenAI key (PowerShell):
    
    setx OPENAI_API_KEY "sk-..."
    $env:OPENAI_API_KEY="sk-..."

3) Run directly:

    set NODE_OPTIONS=--max-old-space-size=512
    node server.cjs --model gpt-4o-realtime-preview --input-audio-format pcm16 --output-audio-format pcm16 --port 8765 --verbose

Or with PM2:

    pm2 start ecosystem.config.cjs
    pm2 logs unity-gateway
    pm2 restart unity-gateway
    pm2 stop unity-gateway
    pm2 delete unity-gateway

Unity
-----
- Keep your **RealtimeVoiceClient** sending audio frames to the gateway. The gateway accepts **binary PCM16** frames or JSON `{ type: "input_audio_buffer.append", audio: "<base64>" }` events.
- The gateway will **override formats** to strings and forward everything to the Realtime model.
- If your mic runs at 44.1kHz, it still works; the gateway commits on a timer and does not buffer unbounded audio.
- Recommended long-term: sample mic at **24kHz** in Unity to match the model.

