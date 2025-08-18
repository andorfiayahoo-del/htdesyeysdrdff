
UNITY GATEWAY FIX (memory + invalid_type + keepalive) — drop-in

Files:
- server.cjs   (new robust gateway)
- config.json  (clean, string formats for audio)
- package.json (ws dependency + PM2 scripts)
- ecosystem.config.cjs (optional PM2 config with memory cap)

INSTALL / UPDATE
1) Put these files into your Gateway folder:
   C:\Users\ander\My project\GatewayCJS\
   Overwrite the existing server.cjs / config.json if present.

2) Install deps (one-time):
   cd "C:\Users\ander\My project\GatewayCJS"
   npm i

3) Ensure OPENAI_API_KEY is set for PM2 (PowerShell example):
   setx OPENAI_API_KEY "sk-..."
   (restart your shell after setx, or pass --update-env to PM2)

4) Clean start the gateway:
   pm2 delete unity-gateway 2>NUL
   pm2 start server.cjs --name unity-gateway --update-env

   (Or use the ecosystem file:)
   pm2 start ecosystem.config.cjs

WHAT CHANGED
- Upstream session.update uses:
    input_audio_format: "pcm16"
    output_audio_format: "pcm16"
  (prevents 'invalid_type' error)

- No unbounded buffering: audio frames are forwarded immediately and
  DROPPED if upstream is closed or back-pressured (bufferedAmount>~1MB).
  This stops the growing heap that crashed Node.

- Keepalives: periodic ws.ping to upstream and Unity sides to avoid
  'keepalive ping timeout' disconnects.

- Commit timer: gateway sends input_audio_buffer.commit every ~1.2s when there was recent audio,
  without collecting large arrays in RAM.

OPTIONAL (memory guardrail)
- PM2 memory cap: max_memory_restart=800M in ecosystem file.
  If something goes wrong, PM2 will restart before the heap explodes.

RUN COMMAND (good defaults)
node server.cjs \
  -- (no flags needed; read config.json)

PM2 quick command you already use:
pm2 start server.cjs --name unity-gateway --update-env

Unity side:
- Keep your client sending 'session.update' for voice/instructions only;
  the gateway will sanitize formats and send a clean update upstream.
