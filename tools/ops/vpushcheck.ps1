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

  # 0) Remember HEAD BEFORE push (so we can diff that..HEAD later)
  $preHead = (& git rev-parse HEAD 2>&1).Trim()

  # 1) Push + strict RAW verify (blocks until RAW serves exact bytes)
  git -C "$RepoRoot" vpush
  $head = (& git rev-parse HEAD 2>&1).Trim()
  OK "Strict verify passed for HEAD=$head"

  # 2) Determine files to check
  $targets = @()
  if ($RelPaths -and $RelPaths.Count -gt 0) {
    $targets = $RelPaths
  } else {
    # Use range diff (preHead..HEAD) so an extra log-only commit at HEAD doesn't mask real changes
    $nameStatus = (& git diff --name-status -M -C $preHead..$head 2>&1) -split "`r?`n"
    foreach($ln in $nameStatus){
      if([string]::IsNullOrWhiteSpace($ln)){ continue }
      $parts = $ln -split "`t"
      if($parts.Length -lt 2){ continue }
      $code = $parts[0]
      if($code -like "D*"){ continue } # skip deletes entirely
      $p = if($code -like "R*" -or $code -like "C*"){ $parts[-1] } else { $parts[1] }
      if([string]::IsNullOrWhiteSpace($p)){ continue }
      if($p -match "^(Library/|ops/live/)"){ continue }
      $targets += ,$p
    }
    $targets = @($targets | Select-Object -Unique)
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
    if ($LASTEXITCODE -eq 3) { $anyMismatch = $true }
  }
  if ($anyMismatch) { ERR "One or more files mismatched."; exit 3 }
  OK "All checked files match blob + RAW."; exit 0
}
finally { Pop-Location }
