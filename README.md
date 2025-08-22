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

<!--  -->
### Sync Guard (no timers)

- **post-commit hook:** auto-push to origin main.
- **pre-push hook:** runs Health Guard; blocks bad pushes.
- **flush wrapper:** after router apply, performs an opportunistic sync.

_sync-stamp: 

<!--  -->


$hook test: 2025-08-22T12:46:51.3808961+02:00
