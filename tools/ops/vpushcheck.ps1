param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch     = 'main',
  [string]$RemoteName = 'origin',
  [string[]]$RelPaths = @(),
  [switch]$NoNormalizeWorkingFile,
  [switch]$NoList
)
$ErrorActionPreference = 'Stop'
function OK($m){   Write-Host "[OK]   $m" -ForegroundColor Green }
function WARN($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ERR($m){  Write-Host "[ERR]  $m" -ForegroundColor Red }
Push-Location -LiteralPath $RepoRoot
try {
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "Not a git work tree: $RepoRoot" }

  # 0) Remember HEAD BEFORE push (so we can diff that..HEAD later)
  $preHead = (& git rev-parse HEAD 2>$null).Trim()

  # 1) Push + strict RAW verify (blocks until RAW serves exact bytes)
  git -C "$RepoRoot" vpush
  $head = (& git rev-parse HEAD 2>$null).Trim()
  OK "Strict verify passed for HEAD=$head"

  # 2) Determine files to check
  $targets = @()
  if ($RelPaths -and $RelPaths.Count -gt 0) {
    $targets = $RelPaths
  } else {
    # Helper: parse a NUL-separated --name-status stream into target paths
    function ParseNameStatusZ([string]$joined){
      $tok = $joined -split "`0", [System.StringSplitOptions]::RemoveEmptyEntries
      $out = New-Object System.Collections.Generic.List[string]
      for ($i = 0; $i -lt $tok.Length; ) {
        $code = $tok[$i]; $i++
        if ([string]::IsNullOrWhiteSpace($code)) { continue }
        if ($code -like "D*") { if ($i -lt $tok.Length) { $i++ }; continue }  # skip deletes
        if ($code -like "R*" -or $code -like "C*") {
          if ($i + 1 -ge $tok.Length) { break }
          $old = $tok[$i]; $new = $tok[$i+1]; $i += 2
          $p = $new
        } else {
          if ($i -ge $tok.Length) { break }
          $p = $tok[$i]; $i++
        }
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($p -match "^(Library/|ops/live/)") { continue }
        [void]$out.Add($p)
      }
      ,(@($out | Select-Object -Unique))
    }

    # Primary: diff prePush..HEAD (catches cases where an extra log-only commit lands at HEAD)
    $joined = (& git diff --name-status -z -M -C "$preHead..$head" 2>$null)
    if ($LASTEXITCODE -ne 0) { $joined = "" }
    if ($joined -is [array]) { $joined = [string]::Concat($joined) }
    $targets = ParseNameStatusZ $joined

    # Fallback: if no targets (common when push didn't create a new commit), use HEAD's tree
    if (-not $targets -or $targets.Count -eq 0) {
      $joined2 = (& git diff-tree --no-commit-id --name-status -z -r -M -C $head 2>$null)
      if ($LASTEXITCODE -ne 0) { $joined2 = "" }
      if ($joined2 -is [array]) { $joined2 = [string]::Concat($joined2) }
      $targets = ParseNameStatusZ $joined2
    }
  }

  $targets = @($targets | Where-Object { $_ } | Select-Object -Unique)
  if (-not $NoList) {
    Write-Host ("Targets to check ({0}):" -f $targets.Count) -ForegroundColor Cyan
    foreach($t in $targets){ Write-Host ("  - {0}" -f $t) }
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
