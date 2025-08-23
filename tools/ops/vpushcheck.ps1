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

  # 0) Remember HEAD BEFORE push
  $preHead = (& git rev-parse HEAD 2>$null).Trim()

  # 1) Push + strict RAW verify
  git -C "$RepoRoot" vpush
  $head = (& git rev-parse HEAD 2>$null).Trim()
  OK "Strict verify passed for HEAD=$head"

  # helper: parse NUL-separated name-status to target paths (skip deletes, take NEW path for R/C)
  function Parse-NameStatusZ([string]$joined){
    $tok = $joined -split "`0", [System.StringSplitOptions]::RemoveEmptyEntries
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $tok.Length; ) {
      $code = $tok[$i]; $i++
      if ([string]::IsNullOrWhiteSpace($code)) { continue }
      if ($code -like "D*") { if ($i -lt $tok.Length) { $i++ }; continue }
      if ($code -like "R*" -or $code -like "C*") {
        if ($i + 1 -ge $tok.Length) { break }
        $old = $tok[$i]; $new = $tok[$i+1]; $i += 2; $p = $new
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
  function Join-Out($raw){ if ($raw -is [array]) { [string]::Concat($raw) } else { [string]$raw } }

  # Flexible -RelPaths handling (CSV/SSV/JSON accepted via git alias)
  if ($RelPaths -and $RelPaths.Count -eq 1) {
    $s = $RelPaths[0].Trim()
    if ($s.StartsWith("[")) { try { $RelPaths = @((ConvertFrom-Json $s)) } catch {} }
    elseif ($s -match "[,;]") {
      $RelPaths = @($s -split "\s*[,;]\s*" | ForEach-Object { $_.Trim("'""") } )
    }
  }

  # 2) Determine files to check
  $targets = @()
  if ($RelPaths -and $RelPaths.Count -gt 0) {
    $targets = $RelPaths
  } else {
    # (a) Files from the *range* preHead..head (post-push commits, e.g., log-only)
    $r1 = (& git diff --name-status -z -M -C "$preHead..$head" 2>$null); if ($LASTEXITCODE -ne 0) { $r1 = "" }
    $targets += Parse-NameStatusZ (Join-Out $r1)

    # (b) Files from the *pre-push commit itself* (so it can't be masked by a log-only HEAD)
    $r2 = (& git diff-tree --no-commit-id --name-status -z -r -M -C $preHead 2>$null); if ($LASTEXITCODE -ne 0) { $r2 = "" }
    $targets += Parse-NameStatusZ (Join-Out $r2)
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
