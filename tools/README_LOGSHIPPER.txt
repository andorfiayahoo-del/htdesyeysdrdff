Log Shipper + Gateway bundle
================================

Folders:
- GatewayCJS\       → Node gateway (server.cjs)
- tools\            → log shipper scripts

Quick start (Gateway)
---------------------
1) Move 'GatewayCJS' into your Unity project root (same level as Assets/).
2) Open a new terminal and run:

   cd "<your project>\GatewayCJS"
   npm i
   set OPENAI_API_KEY=sk-...your key...
   set NODE_OPTIONS=--max-old-space-size=512
   node server.cjs --model gpt-4o-realtime-preview --input-audio-format pcm16 --output-audio-format pcm16 --port 8765 --verbose

   (or with PM2)
   pm2 start ecosystem.config.cjs --update-env

Log shipper
-----------
- One-off run:
  tools\ship_logs.bat

  Output zip lands in: '<project>\LogsOutbox' by default.

- To auto-sync elsewhere, set an env var before running:
  set LOG_SHIP_DEST=C:\Users\<you>\OneDrive\SharedLogs
  tools\ship_logs.bat

- Schedule hourly:
  Run tools\setup_schtasks.bat as Administrator.

What gets collected
-------------------
- Editor.log / Editor-prev.log
- Player.log (LocalLow\*\*\Player.log)
- Crash dumps under %LOCALAPPDATA%\Temp\Unity\Editor\Crashes
- PM2 logs (~\.pm2\logs\*.log)
- ProjectSettings\ProjectVersion.txt
- Anything under '<project>\Logs\**\*.*' if present
- A manifest.json with environment + list of collected files
