# Handover & Assistant Guide (Canonical)

This document is the **source of truth** for how assistants and humans work in this repo.

## 1) Default Operating Mode: JDI (Just Do It)

Default: For any low-risk, non-destructive, easily reversible change, assistants should implement it immediately without asking.
Examples:
- Fix typos; clarify comments; improve docs.
- Normalize line endings per repo policy; fix encoding warnings.
- Add tiny helper scripts or idempotent ops improvements.
- Remove or silence harmless warnings; improve logging and traceability.
- Update `.gitattributes` or `.editorconfig` to match policy.

Notify: After a JDI change, post a short summary plus the exact commands, and when sensible a one-liner to revert.

### Ask-First Triggers
- Destructive changes (deletions or renames with behavior or data impact).
- Anything touching security, secrets, or credentials.
- Changes that add cost or external service impact.
- Altering verification semantics or branch protections.
- Big structural refactors or behavior-altering logic.
- Anything likely to surprise a maintainer.

### When in doubt
If the risk is not near-zero or revert is not trivial, ask first.

---

## 2) Owner Preferences (Ander)
- Keep responses concise with paste-ready code blocks.
- Default to JDI (do not ask for obvious, no-downside fixes).
- Use PowerShell 7+ (pwsh).
- EOL policy:
  - PowerShell scripts (*.ps1, *.psm1, *.psd1, *.bat, *.cmd) -> CRLF
  - Repo meta and dotfiles (.editorconfig, .gitattributes, .gitignore) and shell scripts (*.sh, *.bash) -> LF
  - UTF-8 (no BOM), final newline, trim trailing whitespace.
- Ops pipeline:
  - tools/ops/git-sync.ps1 integrated with `git vpush` -> commit, push, verify.
  - Verification logs: ops/live/push-flush.log (RID-stamped).
- Content helper: tools/ops/ContentHelpers.psm1 -> Set-ContentLF for LF-only writes when needed.

Commit messages:
- sync: auto (REASON) 2025-01-02T03:04:05.678Z for ops auto-commits
- docs: ..., ops: ..., repo: ... for manual intent
- Factual and terse.

---

## 3) Copy/Paste Safety (Hard Rule)
- Never use PowerShell here-strings in chat code.
- Prefer arrays + `Set-ContentLF -Lines` or for large blobs Base64 decode.
- Keep scripts idempotent and re-runnable.

---

## 4) Conventions & Guardrails
- .gitattributes and .editorconfig pin EOL and formatting; follow them.
- Encoding: UTF-8 (no BOM).
- Logs: Structured, RID-tagged; avoid noisy stdout unless useful.
- Verification: tools/ops/verify-remote.ps1 runs after push and must exit 0; output is folded into push-flush.log.

---

## 5) Quick Recipes

### Write a file with LF newlines
```powershell
Import-Module (Join-Path $PSScriptRoot "tools/ops/ContentHelpers.psm1") -Force
Set-ContentLF -Path (Join-Path $RepoRoot ".gitattributes") -Lines @(
  '* text=auto',
  '*.ps1  text eol=crlf','*.psm1 text eol=crlf','*.psd1 text eol=crlf',
  '*.bat  text eol=crlf','*.cmd  text eol=crlf',
  '*.sh   text eol=lf','*.bash text eol=lf',
  '.editorconfig text eol=lf','.gitattributes text eol=lf','.gitignore text eol=lf'
)
```

### Commit, push, and verify
```powershell
git -C "$RepoRoot" vpush
Get-Content "$RepoRoot\ops\live\push-flush.log" -Tail 80
```

### Sentinel sanity
```powershell
$sentinel = Join-Path $RepoRoot "ops\verify-sentinel.txt"
"hello $(Get-Date -Format o)" | Set-Content -LiteralPath $sentinel -Encoding utf8
git -C "$RepoRoot" vpush
Remove-Item -LiteralPath $sentinel -ErrorAction SilentlyContinue
git -C "$RepoRoot" vpush
```

---

## 6) Onboarding (new assistant or human)
1. Read this Handover. Default to JDI.
2. Do a tiny no-risk change, commit via vpush, confirm verify passes.
3. Use the recipes above; prefer paste-ready code in updates.

---

## 7) Rollback and Recovery
- Revert last commit (safe): `git revert <sha>`
- Hard reset local (dangerous): `git reset --hard <sha>`
- If verification fails, check ops/live/push-flush.log for VERIFY_* lines.