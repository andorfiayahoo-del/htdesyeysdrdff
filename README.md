<!-- HANDOVER-BANNER v1 -->
> 🚨 **MANDATORY FOR ALL ASSISTANTS:** Read **ALL** handover materials **before doing anything**.
> Start here → **[handover/Handover-Instructions.md](handover/Handover-Instructions.md)**
> Local folder C:\Users\ander\My project and this GitHub repo **must ALWAYS be in sync**.
> Loop (event-driven, **no timers**): **patch → apply → push**.
<!-- /HANDOVER-BANNER -->
# Project Handover

**MUST read ALL the handover information** before doing anything else.

This repository and the local folder **must always be in sync**:
- Authoritative local folder: C:\Users\ander\My project
- Public GitHub (read-only for assistants): https://github.com/andorfiayahoo-del/htdesyeysdrdff

**Loop (event-driven, no timer):** patch → apply → push
1) Assistant proposes a patch (saved as Downloads\patch_XXXXX.patch).
2) Router attempts apply.
3) On success or attempted apply, logs are pushed immediately to this repo.
4) Assistant reads new logs and iterates.

<!-- sync-stamp: 2025-08-22T08:02:11.505Z -->

<!-- REPAIR-RECONNECT:BEGIN -->
### Quick Repair / Reconnect (no timers)
If Git disconnects (you’ll see ops/live/GIT-DISCONNECTED.txt or GIT_HEALTH_FAIL in ops/live/push-flush.log):

1) Open PowerShell in C:\Users\ander\My project
2) Run:  
   pwsh -NoProfile -ExecutionPolicy Bypass -File tools\ops\repair-reconnect.ps1
3) Re-run the patch → apply → push loop.

This repo uses event-driven guards:
- **pre-push** runs a Git **health check** (blocks bad pushes)
- **post-commit** auto-pushes to origin main
<!-- REPAIR-RECONNECT:END -->


$hook test: 2025-08-22T12:46:51.3808961+02:00

<!--  -->
### Access Flow (no agent tools required)
Assistants must access the repo via public GitHub URLs (blob/raw), like any website:
- Repo: https://github.com/andorfiayahoo-del/htdesyeysdrdff
- RAW base: https://raw.githubusercontent.com/andorfiayahoo-del/htdesyeysdrdff/main

Do **not** depend on ChatGPT agent/browser integrations. If browsing tools are unavailable,
state clearly: “I'll use the public raw/blob URLs instead.”
_sync-stamp: 
<!--  -->





$strict verify ping: 2025-08-22T19:34:05.3068036+02:00
$cdn verify test 2025-08-22T22:26:35.4036130+02:00

local edit 2025-08-23T18:08:04.3813065+02:00
