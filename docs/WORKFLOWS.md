# Workflows

## Canary Patch + Verify (Primary)
1) **Create tiny test patch**: `patch-minforce.ps1` adds `ForceCompile_*.cs`
2) **Wait for Unity compile**: focus/idle detection via user32; writes sentinel
3) **Validate match**: `step-validate-match.ps1` → `ops/live/match.json` (arrays for mismatches/missing)
4) **Verify & push**: `git vpush` → `ops/live/push-flush.log` (STRICT_OK & health)

### Expected Markers
- `[unity-focus] Unity focused — waiting for compile completion...`
- `[validate-match] matched=1 mismatched=0 missing=0`
- `VERIFY_STRICT_OK` and `GIT_VERIFY_OK`

### Logs
- `ops/live/push-flush.log`
- `ops/live/unity-compile.json`
- `ops/live/match.json`

### Router
No external patch **router** is used in this repo; stick to the canary + `vpush`.
