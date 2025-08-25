# Project Ops & Unity Handshake — Quickstart

This repo is instrumented so failures **auto-capture and push** logs to `ops/live/`, and Unity compiles can be **reliably triggered and verified** from PowerShell.

## TL;DR

- Safe wrapper (captures transcript + errors; pushes on failure):

~~~pwsh
$RepoRoot = "C:\Users\ander\My project"
pwsh -NoProfile -File "$RepoRoot/tools/ops/safepush-run.ps1" -RepoRoot "$RepoRoot" -Cmd 'pwsh -NoProfile -File "some\script.ps1"'
~~~

- Force Unity recompile & wait until it’s really done (DidReloadScripts ack + DLL/log checks + stabilization):

~~~pwsh
$RepoRoot = "C:\Users\ander\My project"
$Cmd = "pwsh -NoProfile -File `"$RepoRoot/tools/ops/patch-minforce.ps1`" -ProjectRoot `"$RepoRoot`" -TimeoutSec 600"
pwsh -NoProfile -File "$RepoRoot/tools/ops/safepush-run.ps1" -RepoRoot "$RepoRoot" -Cmd $Cmd
~~~

## Where to look

- `ops/live/latest-error.md` — snapshot of most recent error (RID, status, file/line when known, transcript tail).
- `ops/live/latest-pointer.json` — machine pointer with paths:

~~~json
{
  "rid": "2025...-<guid>",
  "status": "ERROR",
  "head": "<git sha>",
  "file": "C:\\...\\failing-script.ps1",
  "line": "36",
  "files": {
    "error_md": "C:\\...\\ops\\live\\latest-error.md",
    "transcript": "C:\\...\\ops\\live\\transcript_<rid>.log",
    "error_txt": "C:\\...\\ops\\live\\error_<rid>.txt"
  }
}
~~~

- `ops/live/transcript_*.log` — full console transcript per run  
- `ops/live/error_*.txt` — raw exception text  
- Helper: `tools/ops/show-latest.ps1`

## Error-capture pipeline

**Wrapper** `tools/ops/safepush-run.ps1`

- Starts transcript, runs your command, captures failures (incl. native exits), writes `error_<RID>.txt`.
- Calls `tools/ops/publish-latest-error.ps1` **non-fatally** (publisher exit forced to 0); synthesizes `latest-*` if needed.
- Adds/commits/pushes artifacts on failure; exits **2**.

**Publisher** `tools/ops/publish-latest-error.ps1`

- Always **exits 0**.  
- Builds `latest-error.md`; extracts File/Line from ParserError `<path>:<line>`, runtime `At <path>:<line> char:`, or table `Line | <n> |`; infers file from `EXEC:` when needed.  
- Writes `latest-pointer.json`.

## Unity compile handshake

- **Editor sentinel** `Assets/Ops/Editor/OpsCompileSignal.cs` — `[DidReloadScripts]` ACK after script reload → writes `ops/live/compile-ack_<token>.txt` when `ops/live/compile-trigger.txt` contains the token.
- **Trigger & Wait** `tools/ops/patch-minforce.ps1`  
  - Drops `Assets/Ops/PatchTest/ForceCompile_<stamp>.cs` to force compile.  
  - Writes unique token to `ops/live/compile-trigger.txt`.  
  - Waits for **ACK (fresh)** **AND** (**DLL timestamp change** or fresh `Editor.log` completion messages), then requires **1.5s stabilization** with no new DLL/log writes.  
  - Best-effort focuses Unity. On success prints `[validate] compile detected — OK`.

Cleanup: `tools/ops/cleanup-live.ps1` backs up + prunes old `compile-ack_*.txt` (>7 days).

## Stress tests

See `tools/ops/tests/` and `tools/ops/tests/run-error-matrix.ps1` (bad parse, runtime throw, native fail, exit 1, missing command, pipeline div/0, non-terminating).

## Conventions

- UTF-8 (no BOM); CRLF ok.  
- Wrapper commits to `main` (uses `git alias vpush` when present).  
- Exit codes: success `0`, wrapper error `2`.