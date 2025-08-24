# tools/ops/Write-Handover.ps1
param([string]$RepoRoot = (Get-Location).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8Lf {
  [CmdletBinding(DefaultParameterSetName='Lines')]
  param(
    [Parameter(Mandatory,Position=0)] [string]$Path,
    [Parameter(Mandatory,ParameterSetName='Lines',Position=1)] [string[]]$Lines,
    [Parameter(Mandatory,ParameterSetName='Text', Position=1)] [string]$Text
  )
  $dir = Split-Path -LiteralPath $Path
  if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  if ($PSCmdlet.ParameterSetName -eq 'Lines') { $Text = ($Lines -join "`n") }
  $Text = $Text -replace "`r`n","`n"
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $utf8)
}

$HandoverRel = 'docs/HANDOVER.md'
$Handover    = Join-Path $RepoRoot $HandoverRel
[IO.Directory]::CreateDirectory((Split-Path -LiteralPath $Handover)) | Out-Null

$L = @()
$L += '# Handover & Assistant Guide (Canonical)'
$L += ""
$L += 'This document is the **source of truth** for how assistants and humans work in this repo.'
$L += ""
$L += '## 1) Default Operating Mode: JDI (Just Do It)'
$L += ""
$L += 'Default: For any low-risk, non-destructive, easily reversible change, assistants should implement it immediately without asking.'
$L += 'Examples:'
$L += '- Fix typos; clarify comments; improve docs.'
$L += '- Normalize line endings per repo policy; fix encoding warnings.'
$L += '- Add tiny helper scripts or idempotent ops improvements.'
$L += '- Remove or silence harmless warnings; improve logging and traceability.'
$L += '- Update `.gitattributes` or `.editorconfig` to match policy.'
$L += ""
$L += 'Notify: After a JDI change, post a short summary plus the exact commands, and when sensible a one-liner to revert.'
$L += ""
$L += '### Ask-First Triggers'
$L += '- Destructive changes (deletions or renames with behavior or data impact).'
$L += '- Anything touching security, secrets, or credentials.'
$L += '- Changes that add cost or external service impact.'
$L += '- Altering verification semantics or branch protections.'
$L += '- Big structural refactors or behavior-altering logic.'
$L += '- Anything likely to surprise a maintainer.'
$L += ""
$L += '### When in doubt'
$L += 'If the risk is not near-zero or revert is not trivial, ask first.'
$L += ""
$L += '---'
$L += ""
$L += '## 2) Owner Preferences (Ander)'
$L += '- Keep responses concise with paste-ready code blocks.'
$L += '- Default to JDI (do not ask for obvious, no-downside fixes).'
$L += '- Use PowerShell 7+ (pwsh).'
$L += '- EOL policy:'
$L += '  - PowerShell scripts (*.ps1, *.psm1, *.psd1, *.bat, *.cmd) -> CRLF'
$L += '  - Repo meta and dotfiles (.editorconfig, .gitattributes, .gitignore) and shell scripts (*.sh, *.bash) -> LF'
$L += '  - UTF-8 (no BOM), final newline, trim trailing whitespace.'
$L += '- Ops pipeline:'
$L += '  - tools/ops/git-sync.ps1 integrated with "git vpush" -> commit, push, verify.'
$L += '  - Verification logs: ops/live/push-flush.log (RID-stamped).'
$L += '- Content helper: tools/ops/ContentHelpers.psm1 -> Set-ContentLF for LF-only writes when needed.'
$L += ""
$L += 'Commit messages:'
$L += '- sync: auto (REASON) 2025-01-02T03:04:05.678Z for ops auto-commits'
$L += '- docs: ..., ops: ..., repo: ... for manual intent'
$L += '- Factual and terse.'
$L += ""
$L += '---'
$L += ""
$L += '## 3) Copy/Paste Safety (Hard Rule)'
$L += '- Never use PowerShell here-strings in chat code.'
$L += '- Prefer arrays + `Set-ContentLF -Lines` or for large blobs Base64 decode.'
$L += '- Keep scripts idempotent and re-runnable.'
$L += ""
$L += '---'
$L += ""
$L += '## 4) Conventions & Guardrails'
$L += '- .gitattributes and .editorconfig pin EOL and formatting; follow them.'
$L += '- Encoding: UTF-8 (no BOM).'
$L += '- Logs: Structured, RID-tagged; avoid noisy stdout unless useful.'
$L += '- Verification: tools/ops/verify-remote.ps1 runs after push and must exit 0; output is folded into push-flush.log.'
$L += ""
$L += '---'
$L += ""
$L += '## 5) Quick Recipes'
$L += ""
$L += '### Write a file with LF newlines'
$L += '```powershell'
$L += 'Import-Module (Join-Path $PSScriptRoot "tools/ops/ContentHelpers.psm1") -Force'
$L += 'Set-ContentLF -Path (Join-Path $RepoRoot ".gitattributes") -Lines @('
$L += '  "* text=auto",'
$L += '  "*.ps1  text eol=crlf","*.psm1 text eol=crlf","*.psd1 text eol=crlf",'
$L += '  "*.bat  text eol=crlf","*.cmd  text eol=crlf",'
$L += '  "*.sh   text eol=lf","*.bash text eol=lf",'
$L += '  ".editorconfig text eol=lf",".gitattributes text eol=lf",".gitignore text eol=lf"'
$L += ')'
$L += '```'
$L += ""
$L += '### Commit, push, and verify'
$L += '```powershell'
$L += 'git -C "$RepoRoot" vpush'
$L += 'Get-Content "$RepoRoot\ops\live\push-flush.log" -Tail 80'
$L += '```'
$L += ""
$L += '### Sentinel sanity'
$L += '```powershell'
$L += '$sentinel = Join-Path $RepoRoot "ops\verify-sentinel.txt"'
$L += '"hello $(Get-Date -Format o)" | Set-Content -LiteralPath $sentinel -Encoding utf8'
$L += 'git -C "$RepoRoot" vpush'
$L += 'Remove-Item -LiteralPath $sentinel -ErrorAction SilentlyContinue'
$L += 'git -C "$RepoRoot" vpush'
$L += '```'
$L += ""
$L += '---'
$L += ""
$L += '## 6) Onboarding (new assistant or human)'
$L += '1. Read this Handover. Default to JDI.'
$L += '2. Do a tiny no-risk change, commit via vpush, confirm verify passes.'
$L += '3. Use the recipes above; prefer paste-ready code in updates.'
$L += ""
$L += '---'
$L += ""
$L += '## 7) Rollback and Recovery'
$L += '- Revert last commit (safe): `git revert <sha>`'
$L += '- Hard reset local (dangerous): `git reset --hard <sha>`'
$L += '- If verification fails, check ops/live/push-flush.log for VERIFY_* lines.'

if (-not ($L -and $L.Count)) { throw "Internal: Handover content was empty." }
Write-Utf8Lf -Path $Handover -Lines $L

$Readme = Join-Path $RepoRoot 'README.md'
if (Test-Path -LiteralPath $Readme) {
  $existing = Get-Content -LiteralPath $Readme -Raw
  if ($existing -notmatch [regex]::Escape($HandoverRel)) {
    $append = @(
      ""
      "---"
      ""
      "## Handover & Assistant Guide"
      ""
      "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences."
    ) -join "`n"
    $updated = ($existing.TrimEnd() + "`n" + $append + "`n")
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Readme, ($updated -replace "`r`n","`n"), $utf8)
  }
} else {
  $R = @(
    "# Project"
    ""
    "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences."
  )
  Write-Utf8Lf -Path $Readme -Lines $R
}
