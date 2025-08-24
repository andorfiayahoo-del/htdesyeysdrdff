param([string]$RepoRoot = (Get-Location).Path)

$Handover = Join-Path $RepoRoot "docs\HANDOVER.md"
$Readme   = Join-Path $RepoRoot "README.md"

function Write-Utf8Lf {
  [CmdletBinding(DefaultParameterSetName='Text')]
  param(
    [Parameter(Mandatory,Position=0)] [string]$Path,
    [Parameter(Mandatory,ParameterSetName='Text',Position=1)] [string]$Text
  )
  $dir = Split-Path -LiteralPath $Path
  if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $Text = ($Text -replace "`r`n","`n")
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $utf8)
}

$H = @()
# ---- HANDOVER CONTENT (single-quoted lines, safe for backticks) ----
# 1) JDI default
$H += "# Handover & Assistant Guide (Canonical)"
$H += ""
$H += "This document is the **source of truth** for how assistants and humans work in this repo."
$H += ""
$H += "## 1) Default Operating Mode: JDI (Just Do It)"
$H += ""
$H += "Default: For any low-risk, non-destructive, easily reversible change, assistants should implement it immediately without asking."
$H += "Examples:"
$H += "- Fix typos; clarify comments; improve docs."
$H += "- Normalize line endings per repo policy; fix encoding warnings."
$H += "- Add tiny helper scripts or idempotent ops improvements."
$H += "- Remove or silence harmless warnings; improve logging and traceability."
$H += "- Update `.gitattributes` or `.editorconfig` to match policy."
$H += ""
$H += "Notify: After a JDI change, post a short summary plus the exact commands, and when sensible a one-liner to revert."
$H += ""
$H += "### Ask-First Triggers"
$H += "- Destructive changes (deletions or renames with behavior or data impact)."
$H += "- Anything touching security, secrets, or credentials."
$H += "- Changes that add cost or external service impact."
$H += "- Altering verification semantics or branch protections."
$H += "- Big structural refactors or behavior-altering logic."
$H += "- Anything likely to surprise a maintainer."
$H += ""
$H += "### When in doubt"
$H += "If the risk is not near-zero or revert is not trivial, ask first."
$H += ""
$H += "---"
$H += ""
# 2) Preferences
$H += "## 2) Owner Preferences (Ander)"
$H += "- Keep responses concise with paste-ready code blocks."
$H += "- Default to JDI (do not ask for obvious, no-downside fixes)."
$H += "- Use PowerShell 7+ (pwsh)."
$H += "- EOL policy:"
$H += "  - PowerShell scripts (*.ps1, *.psm1, *.psd1, *.bat, *.cmd) -> CRLF"
$H += "  - Repo meta and dotfiles (.editorconfig, .gitattributes, .gitignore) and shell scripts (*.sh, *.bash) -> LF"
$H += "  - UTF-8 (no BOM), final newline, trim trailing whitespace."
$H += "- Ops pipeline:"
$H += "  - tools/ops/git-sync.ps1 integrated with `git vpush` -> commit, push, verify."
$H += "  - Verification logs: ops/live/push-flush.log (RID-stamped)."
$H += "- Content helper: tools/ops/ContentHelpers.psm1 -> Set-ContentLF for LF-only writes when needed."
$H += ""
$H += "Commit messages:"
$H += "- sync: auto (REASON) 2025-01-02T03:04:05.678Z for ops auto-commits"
$H += "- docs: ..., ops: ..., repo: ... for manual intent"
$H += "- Factual and terse."
$H += ""
$H += "---"
$H += ""
# 3) Copy/paste safety
$H += "## 3) Copy/Paste Safety (Hard Rule)"
$H += "- Never use PowerShell here-strings in chat code."
$H += "- Prefer arrays + `Set-ContentLF -Lines` or for large blobs Base64 decode."
$H += "- Keep scripts idempotent and re-runnable."
$H += ""
$H += "---"
$H += ""
# 4) Conventions
$H += "## 4) Conventions & Guardrails"
$H += "- .gitattributes and .editorconfig pin EOL and formatting; follow them."
$H += "- Encoding: UTF-8 (no BOM)."
$H += "- Logs: Structured, RID-tagged; avoid noisy stdout unless useful."
$H += "- Verification: tools/ops/verify-remote.ps1 runs after push and must exit 0; output is folded into push-flush.log."
$H += ""
$H += "---"
$H += ""
# 5) Recipes
$H += "## 5) Quick Recipes"
$H += ""
$H += "### Write a file with LF newlines"
$H += "```powershell"
$H += "Import-Module (Join-Path $PSScriptRoot ""tools/ops/ContentHelpers.psm1"") -Force"
$H += "Set-ContentLF -Path (Join-Path $RepoRoot "".gitattributes"") -Lines @("
$H += "  '* text=auto',"
$H += "  '*.ps1  text eol=crlf','*.psm1 text eol=crlf','*.psd1 text eol=crlf',"
$H += "  '*.bat  text eol=crlf','*.cmd  text eol=crlf',"
$H += "  '*.sh   text eol=lf','*.bash text eol=lf',"
$H += "  '.editorconfig text eol=lf','.gitattributes text eol=lf','.gitignore text eol=lf'"
$H += ")"
$H += "```"
$H += ""
$H += "### Commit, push, and verify"
$H += "```powershell"
$H += "git -C ""$RepoRoot"" vpush"
$H += "Get-Content ""$RepoRoot\ops\live\push-flush.log"" -Tail 80"
$H += "```"
$H += ""
$H += "### Sentinel sanity"
$H += "```powershell"
$H += "$sentinel = Join-Path $RepoRoot ""ops\verify-sentinel.txt"""
$H += "\"\"hello $(Get-Date -Format o)\"\" | Set-Content -LiteralPath $sentinel -Encoding utf8"
$H += "git -C ""$RepoRoot"" vpush"
$H += "Remove-Item -LiteralPath $sentinel -ErrorAction SilentlyContinue"
$H += "git -C ""$RepoRoot"" vpush"
$H += "```"
$H += ""
$H += "---"
$H += ""
# 6) Onboarding + 7) Recovery
$H += "## 6) Onboarding (new assistant or human)"
$H += "1. Read this Handover. Default to JDI."
$H += "2. Do a tiny no-risk change, commit via vpush, confirm verify passes."
$H += "3. Use the recipes above; prefer paste-ready code in updates."
$H += ""
$H += "---"
$H += ""
$H += "## 7) Rollback and Recovery"
$H += "- Revert last commit (safe): `git revert <sha>`"
$H += "- Hard reset local (dangerous): `git reset --hard <sha>`"
$H += "- If verification fails, check ops/live/push-flush.log for VERIFY_* lines."

Write-Utf8Lf -Path $Handover -Text ($H -join "`n")

if (Test-Path -LiteralPath $Readme) {
  $existing = Get-Content -LiteralPath $Readme -Raw
  if ($existing -notmatch [regex]::Escape("docs/HANDOVER.md")) {
    $append = @("", "---", "", "## Handover & Assistant Guide", "", "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences.") -join "`n"
    $updated = ($existing.TrimEnd() + "`n" + $append + "`n")
    Write-Utf8Lf -Path $Readme -Text $updated
  }
} else {
  $R = @("# Project", "", "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences.") -join "`n"
  Write-Utf8Lf -Path $Readme -Text $R
}