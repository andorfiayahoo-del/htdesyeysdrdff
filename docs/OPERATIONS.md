# Operations Handbook

This is the handover for anyone new (or any new assistant instance).

---

## Components

### Wrapper — `tools/ops/safepush-run.ps1`
- Starts transcript; runs command; captures failures (incl. native exits); writes `error_<RID>.txt`.
- Calls publisher without letting its exit code bubble (guarded; forced `exit 0`).
- Synthesizes `latest-error.md` and `latest-pointer.json` if publisher didn’t.
- `git add/commit/push` artifacts on failure; returns exit **2**.

Paths:
- `ops/live/transcript_<RID>.log`
- `ops/live/error_<RID>.txt`
- `ops/live/latest-error.md`
- `ops/live/latest-pointer.json`
- RID format: `yyyyMMddTHHmmss.fffffffZ-<guid>`

### Publisher — `tools/ops/publish-latest-error.ps1`
- Always **exits 0**.
- Extracts File/Line from:
  - `ParserError: <path>:<line>`
  - `At <path>:<line> char:`
  - `Line |  36 |`
  - Fallback from transcript `EXEC: pwsh -NoProfile -File "<path>"`
- Writes `latest-pointer.json` with `{ rid, status, head, file, line, files{...} }`.

### Unity compile handshake
- **Sentinel** `Assets/Ops/Editor/OpsCompileSignal.cs` — `[DidReloadScripts]` ACK → `ops/live/compile-ack_<token>.txt`
- **Trigger & Wait** `tools/ops/patch-minforce.ps1`
  - Force compile file under `Assets/Ops/PatchTest/`
  - Write token to `ops/live/compile-trigger.txt`
  - Wait: **ACK (fresh)** AND (**DLL update** or fresh `Editor.log` completion)
  - Stabilize **1.5s** (no further DLL/log writes)
  - Best-effort focus Unity; on success exit **0**
- **Cleanup** `tools/ops/cleanup-live.ps1` — backup/prune old ack files; leaves transcripts/errors/latest-* untouched

---

## Typical usage

~~~pwsh
# Safe run
$RepoRoot = "C:\Users\ander\My project"
$Cmd = 'pwsh -NoProfile -File "tools\ops\tests\bad-parse.ps1"'
pwsh -NoProfile -File "$RepoRoot/tools/ops/safepush-run.ps1" -RepoRoot "$RepoRoot" -Cmd $Cmd
~~~

~~~pwsh
# Unity recompile & wait
$RepoRoot = "C:\Users\ander\My project"
$Cmd = "pwsh -NoProfile -File `"$RepoRoot/tools/ops/patch-minforce.ps1`" -ProjectRoot `"$RepoRoot`" -TimeoutSec 600"
pwsh -NoProfile -File "$RepoRoot/tools/ops/safepush-run.ps1" -RepoRoot "$RepoRoot" -Cmd $Cmd
~~~

~~~pwsh
# Stress test matrix
$RepoRoot = "C:\Users\ander\My project"
pwsh -NoProfile -File "$RepoRoot/tools/ops/tests/run-error-matrix.ps1"
~~~

---

## Notes

- If Unity isn’t running with this project open, ACK won’t appear; DLL/log may still suffice.
- Increase `-TimeoutSec` for heavy projects.
- CRLF/LF warnings are benign (UTF-8 no BOM preferred).
- Wrapper: success `0`, error `2`.

---

## File map

- `tools/ops/safepush-run.ps1` — safe wrapper (pushes error artifacts)
- `tools/ops/publish-latest-error.ps1` — builds latest-* (exit 0)
- `ops/live/` — transcripts, errors, latest-*, Unity trigger/acks
- `tools/ops/patch-minforce.ps1` — Unity trigger + robust wait + stabilization
- `Assets/Ops/Editor/OpsCompileSignal.cs` — DidReloadScripts ACK
- `tools/ops/cleanup-live.ps1` — backup + prune old ack files
- `tools/ops/tests/` — stress tests; `run-error-matrix.ps1` orchestrator

---

## Handover

Start at `ops/live/latest-pointer.json` → open the files it references.  
For compile reliability, always use `patch-minforce.ps1` via the wrapper.