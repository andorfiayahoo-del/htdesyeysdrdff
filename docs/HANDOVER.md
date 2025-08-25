# Handover & Assistant Guide (Canonical)

This repository is configured for JDI (Just Do It) on low-risk, reversible changes. Use the ops scripts below as the source of truth.

## 1) Default Operating Mode: JDI

- Do it immediately when the change is low-risk, non-destructive, and easy to revert.
- Examples: fix typos, tighten docs, normalize EOL/encoding per policy, add tiny idempotent ops helpers, reduce harmless warnings.
- Notify after doing it (brief summary + exact commands, optional one-liner to revert).

Ask first when the change is destructive, touches security/secrets, adds external cost/quotas, alters verification semantics, or is a big behavior refactor.

## 2) Owner preferences (Ander)

- Keep replies concise with paste-ready code blocks.
- PowerShell 7+ (pwsh).
- Copy/paste safety: do not use here-strings in chat code. Prefer arrays joined with LF/CRLF or small writers.
- EOL policy:
  - PowerShell/C#/batch and Unity .meta files -> CRLF
  - Docs (.md), dotfiles -> LF
  - UTF-8 (no BOM), final newline, trim trailing whitespace.

## 3) Unity: compile-wait integration (current, working)

- Editor sentinel: Assets/Editor/Ops/CompileSentinel.cs writes ops/live/unity-compile.json reflecting isCompiling/isUpdating.
- Waiter: tools/ops/unity-wait-compile.ps1 blocks until both flags are false.
- Focus step: tools/ops/step-wait-unity.ps1 detects when Unity gains focus and then blocks until compile completes (no keypress).
- Validator: tools/ops/step-validate-match.ps1 prints matched/mismatched/missing and fails hard unless -Soft is used.
- Minimal patch driver: tools/ops/patch-minforce.ps1 writes a tiny .cs to force a recompile, then runs the focus+wait step and validator, then your normal vpush flow uploads logs.

Quickstart:

```powershell
$RepoRoot = "C:\Users\ander\My project"
pwsh -NoProfile -File "$RepoRoot\tools\ops\patch-minforce.ps1" -ProjectRoot "$RepoRoot" -TimeoutSec 900
Get-Content "$RepoRoot\ops\live\push-flush.log" -Tail 80
```

What you should see in the log:
- A Unity focus line, then a busy -> idle wait completion.
- A validation line like: [validate-match] matched=1 mismatched=0 missing=0
- The verify job committing ops/live artifacts (push-flush.log, match.json, unity-compile.json).

## 4) Repo map (ops essentials)

- tools/ops/unity-wait-compile.ps1 : sentinel poller, blocks until compile done.
- tools/ops/step-wait-unity.ps1     : cyan UX, auto-detects Unity focus then waits.
- tools/ops/step-validate-match.ps1 : prints matched/mismatched/missing and fails if needed.
- tools/ops/patch-minforce.ps1      : minimal test patch to force a compile, then wait + validate.
- docs/HANDOVER.md                   : this file (canonical).
- ops/live/*                         : verify and runtime logs (committed by vpush flow).

## 5) Conventions and verification

- Follow .gitattributes and .editorconfig. Do not fight the EOL policy.
- Idempotent scripts; safe to re-run.
- Post-push verification runs tools/ops/verify-remote.ps1 and appends to ops/live/push-flush.log, which is committed and pushed automatically.

## 6) Rollback

- Safe: git revert <sha>
- Local reset (dangerous): git reset --hard <sha>
- If verification fails, check ops/live/push-flush.log for VERIFY_* lines.
