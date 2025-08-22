<!-- HANDOVER-BANNER v1 -->
> 🚨 **MANDATORY FOR ALL ASSISTANTS:** Read **ALL** handover materials **before doing anything**.
> Start here → **[handover/Handover-Instructions.md](handover/Handover-Instructions.md)**
> Local folder C:\Users\ander\My project and this GitHub repo **must ALWAYS be in sync**.
> Loop (event-driven, **no timers**): **patch → apply → push**.
<!-- /HANDOVER-BANNER -->
# Handover Instructions (Source of Truth)

**READ THIS ENTIRE FILE.** It is the operational contract for assistants.

## Canonical locations
- Local (authoritative): C:\Users\ander\My project
- GitHub: https://github.com/andorfiayahoo-del/htdesyeysdrdff

**Rule:** Local and Git must **always be in sync**. Write locally → commit → push to origin main.

## Patch → Apply → Push (no timer)
1. Propose a patch the user downloads to Downloads\patch_XXXXX.patch.
2. The router applies it.
3. On success or *attempted* apply, logs are **pushed immediately** to this repo (event-driven).
4. Assistant reads the pushed logs and iterates.

## What to read
- Root README.md (banner + quick links)
- handover\Handover-Instructions.md (this file — canonical)
- handover\Handover-Latest.docx (mirror; optional convenience)
- ops\live\ logs (committed by the apply event)

## Non-negotiables
- PowerShell: pwsh 7.x only
- **No timer** sweepers/collectors
- Assistants only read logs via GitHub; no local access requests.

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



<!--  -->
### Access Flow (no agent tools required)
Assistants must access the repo via public GitHub URLs (blob/raw), like any website:
- Repo: https://github.com/andorfiayahoo-del/htdesyeysdrdff
- RAW base: https://raw.githubusercontent.com/andorfiayahoo-del/htdesyeysdrdff/main

Do **not** depend on ChatGPT agent/browser integrations. If browsing tools are unavailable,
state clearly: “I'll use the public raw/blob URLs instead.”
_sync-stamp: 
<!--  -->





