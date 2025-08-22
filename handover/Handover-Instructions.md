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

<!--  -->
### Sync Guard (no timers)

- **post-commit hook:** auto-push to origin main.
- **pre-push hook:** runs Health Guard; blocks bad pushes.
- **flush wrapper:** after router apply, performs an opportunistic sync.

_sync-stamp: 

<!--  -->


