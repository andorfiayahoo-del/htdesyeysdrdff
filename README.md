# Project Handover & Ops Guide

> **Status:** Green flow using local canary patch + verify. No external router in this repo.

## Source of Truth
- **Default branch:** `main`
- **Live Unity project root:** `C:\Users\ander\My project`
- **Rollbacks:** use commit SHAs from `ops/live/push-flush.log` (tags not used).

## Key Directories
- `tools/ops/` – ops scripts (`patch-minforce.ps1`, `unity-wait-compile.ps1`, `step-validate-match.ps1`, etc.)
- `Assets/Editor/Ops/CompileSentinel.cs` – writes compile sentinel
- `Assets/Ops/PatchTest/` – tiny force-compile test classes
- `ops/live/` – logs & reports (`push-flush.log`, `match.json`, `unity-compile.json`)

## One-Line Smoke Test
```powershell
$RepoRoot = "C:\Users\ander\My project"
pwsh -NoProfile -File "$RepoRoot\tools\ops\patch-minforce.ps1" -ProjectRoot "$RepoRoot" -TimeoutSec 900
Get-Content "$RepoRoot\ops\live\push-flush.log" -Tail 80
```
You should see:
- `[unity-focus] Unity focused — waiting for compile completion...`
- A compile wait that ends when Unity is idle
- `[validate-match] matched=1 mismatched=0 missing=0`
- `VERIFY_STRICT_OK` and `GIT_VERIFY_OK`

## Normal Ops (Docs/Code changes)
1. Edit files (docs or code).
2. `git add` and `git commit` your changes.
3. Run the canary patch to sync Unity state and validate:
   ```powershell
   pwsh -NoProfile -File tools\ops\patch-minforce.ps1 -ProjectRoot "C:\Users\ander\My project" -TimeoutSec 900
   ```
4. Push with verify (**preferred**): `git vpush` (alias runs remote verify and pushes logs).

## Logs & Success Markers
- `ops/live/push-flush.log` – verify + health (expect `VERIFY_STRICT_OK`)
- `ops/live/unity-compile.json` – sentinel
- `ops/live/match.json` – validator report (expect `mismatched=0`, `missing=0`)

## Failure Recovery
- Revert the tiny test file commit (e.g., `Assets/Ops/PatchTest/ForceCompile_*.cs`) or `git revert <sha>`.
- Re-run `patch-minforce.ps1`.

## Not In Scope (Here)
- Unity **voice bridge** (Whisper/Python/etc.) is **not part of this repo**.

## Notes
- EOL normalization is pinned: `.meta` & scripts CRLF; docs LF.
- Avoid here-strings in scripts; prefer explicit line arrays/writers.
