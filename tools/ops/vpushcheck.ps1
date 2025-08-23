param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch     = 'main',
  [string]$RemoteName = 'origin',
  [string[]]$RelPaths = @(),
  [switch]$NoNormalizeWorkingFile
)
$ErrorActionPreference = 'Stop'
function OK($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ERR($m){ Write-Host "[ERR]  $m" -ForegroundColor Red }
Push-Location -LiteralPath $RepoRoot
try {
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "Not a git work tree: $RepoRoot" }

  # 1) Push + strict RAW verify (this blocks until RAW serves exact bytes)
  git -C "$RepoRoot" vpush
  $head = (& git rev-parse HEAD 2>&1).Trim()
  OK "Strict verify passed for HEAD=$head"

  # 2) Determine files to check (changed in HEAD unless explicit RelPaths provided)
  $targets = @()
  if ($RelPaths -and $RelPaths.Count -gt 0) {
    $targets = $RelPaths
  } else {
    $list = (& git diff-tree --no-commit-id --name-only -r HEAD 2>&1)
    $targets = @($list -split "`r?`n" | Where-Object { $_ -and $_ -notmatch "^(Library/|ops/live/)" })
  }
  if ($targets.Count -eq 0) { WARN "No changed files to check."; exit 0 }

  # 3) Check each file: blob vs working vs RAW
  $anyMismatch = $false
  foreach ($rel in $targets) {
    Write-Host ("--- check: {0} ---" -f $rel) -ForegroundColor Cyan
    $args = @('-File', (Join-Path $PSScriptRoot 'check-file-integrity.ps1'),
              '-RepoRoot', $RepoRoot, '-RelPath', $rel,
              '-Owner', $Owner, '-Repo', $Repo, '-Branch', $Branch)
    if ($NoNormalizeWorkingFile) { $args += '-NoNormalizeWorkingFile' }
    & pwsh -NoProfile -ExecutionPolicy Bypass @args
    $code = $LASTEXITCODE
    if ($code -eq 3) { $anyMismatch = $true }
  }
  if ($anyMismatch) { ERR "One or more files mismatched."; exit 3 }
  OK "All checked files match blob + RAW."; exit 0
}
finally { Pop-Location }
