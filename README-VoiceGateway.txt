Unity Realtime Voice – Gateway + Client Patch
=============================================

What this is
------------
A drop-in set of files to fix:
1) Wrong `session.input_audio_format` / `output_audio_format` shape (must be **strings**, e.g. `"pcm16"`).
2) Spurious `input_audio_buffer_commit_empty` by guarding commits until enough audio is appended.
3) `model_not_found` by using a reliable alias: `gpt-4o-realtime-preview`.

What changes
------------
- **Server/** contains a small Node gateway you run locally.
- **Assets/Scripts/Realtime/** contains Unity scripts that:
  - Force the correct `"pcm16"` string formats in `session.update`.
  - Append PCM16 as binary frames.
  - Only commit after at least `MinCommitMs` audio has been appended.
  - Play downstream PCM16 via a ring-buffer player.

Quick start
-----------
1) Unzip this package at your Unity project root.
   - This will place `Server/` next to `Assets/` and may replace two C# files in `Assets/Scripts/Realtime/`.
2) Open a terminal:
   ```bash
   cd Server
   # macOS/Linux
   export OPENAI_API_KEY=sk-...your key...
   ./start-gateway.sh
   # Windows PowerShell
   # setx OPENAI_API_KEY "sk-...your key..."  # (optional persistent)
   .\start-gateway.ps1
   ```
   The gateway listens on `ws://127.0.0.1:8765`.
3) In Unity, press Play. The client defaults to the same URL.

Configuration
-------------
- Edit `Server/config.json` or pass CLI flags:
  - `--model gpt-4o-realtime-preview`
  - `--port 8765`
  - `--min-commit-ms 120`
- The gateway coerces any `session.update` to ensure `"pcm16"` string formats.

Does this replace my old package script?
---------------------------------------
Yes. The included `Server/package.json` is a minimal, standalone replacement for your previous gateway package script.
It **does not** change Unity's `Packages/manifest.json`.

Files
-----
- Server/
  - gateway.js
  - package.json
  - config.json
  - start-gateway.sh
  - start-gateway.ps1
- Assets/Scripts/Realtime/
  - RealtimeVoiceClient.cs
  - StreamingAudioPlayer.cs



v4 Notes (memory + invalid_type fix)
------------------------------------
- The gateway now *never* sends JSON objects for `session.input_audio_format` or `session.output_audio_format`.
  They are strings: "pcm16".
- When upstream is closed, microphone audio is dropped instead of queued. This prevents Node heap growth and OOM.
- PM2 config included: `GatewayCJS/ecosystem.config.cjs` (limits heap to 512MB). Start with:
    pm2 start ecosystem.config.cjs
- If you still prefer raw command: 
    pm2 start server.cjs --name unity-gateway --node-args="--max-old-space-size=512"
