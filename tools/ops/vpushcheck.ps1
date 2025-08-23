param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch     = 'main',
  [string]$RemoteName = 'origin',
  [string[]]$RelPaths = @(),
  [string[]]$Glob     = @(),
  [string]$Since      = '',
  [switch]$NoNormalizeWorkingFile,
  [switch]$NoList,
  [switch]$NoPush,
  [switch]$SkipRaw
)
$ErrorActionPreference = 'Stop'
function OK($m){   Write-Host "[OK]   $m" -ForegroundColor Green }
function WARN($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ERR($m){  Write-Host "[ERR]  $m" -ForegroundColor Red }
Push-Location -LiteralPath $RepoRoot
try {
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "Not a git work tree: $RepoRoot" }

  # Helpers
  function Join-Out($raw){ if ($raw -is [array]) { [string]::Concat($raw) } else { [string]$raw } }
  function Parse-NameStatusZ([string]$joined){
    $tok = $joined -split "`0", [System.StringSplitOptions]::RemoveEmptyEntries
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $tok.Length; ) {
      $code = $tok[$i]; $i++
      if ([string]::IsNullOrWhiteSpace($code)) { continue }
      if ($code -like "D*") { if ($i -lt $tok.Length) { $i++ }; continue } # skip deletes
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
  function Normalize-ListParam([string[]]$arr){
    if (-not $arr -or $arr.Count -ne 1) { return $arr }
    $s = $arr[0].Trim()
    if ($s.StartsWith("[")) {
      try { return @((ConvertFrom-Json $s)) } catch { return ,$s }
    }
    if ($s -match "[,;]") {
      return @($s -split "\s*[,;]\s*" | ForEach-Object { $_.Trim("'""") } )
    }
    return ,$s
  }
  function Ensure-GlobPrefix([string]$p){ if ($p -like ':(glob)*'){ $p } else { ':(glob)' + $p } }

  # 0) Remember HEAD before optional push
  $preHead = (& git rev-parse HEAD 2>$null).Trim()

  # 1) Optional push + strict RAW verify
  if (-not $NoPush) {
    git -C "$RepoRoot" vpush
    $head = (& git rev-parse HEAD 2>$null).Trim()
    OK "Strict verify passed for HEAD=$head"
  } else {
    $head = $preHead
    WARN "NoPush: skipping push/strict RAW verify"
  }

  # If NoPush + not explicitly SkipRaw, auto-disable RAW if remote != local
  if ($NoPush -and -not $SkipRaw) {
    $remote = (& git ls-remote $RemoteName ("refs/heads/$Branch") 2>$null).Trim()
    $remoteSha = if([string]::IsNullOrWhiteSpace($remote)){ "" } else { ($remote -split "\s+")[0] }
    if ($remoteSha -ne $head) {
      WARN "NoPush with remote[$Branch]=$remoteSha != local=$head → RAW check disabled to avoid false mismatches."
      $SkipRaw = $true
    }
  }

  # Flexible inputs
  $RelPaths = Normalize-ListParam $RelPaths
  $Glob     = Normalize-ListParam $Glob

  # 2) Determine files to check
  $targets = New-Object System.Collections.Generic.List[string]

  if ($RelPaths -and $RelPaths.Count -gt 0) {
    foreach($p in $RelPaths){ if($p){ [void]$targets.Add($p) } }
  } else {
    if ($Since) {
      # Everything since <rev> up to $head
      $r = (& git diff --name-status -z -M -C "$Since..$head" 2>$null); if ($LASTEXITCODE -ne 0) { $r = "" }
      foreach($p in (Parse-NameStatusZ (Join-Out $r))){ [void]$targets.Add($p) }
    } else {
      # Union: (a) range preHead..head  +  (b) preHead commit itself
      $r1 = (& git diff --name-status -z -M -C "$preHead..$head" 2>$null); if ($LASTEXITCODE -ne 0) { $r1 = "" }
      foreach($p in (Parse-NameStatusZ (Join-Out $r1))){ [void]$targets.Add($p) }
      $r2 = (& git diff-tree --no-commit-id --name-status -z -r -M -C $preHead 2>$null); if ($LASTEXITCODE -ne 0) { $r2 = "" }
      foreach($p in (Parse-NameStatusZ (Join-Out $r2))){ [void]$targets.Add($p) }
    }
  }

  # Add -Glob matches (tracked files, NUL safe)
  if ($Glob -and $Glob.Count -gt 0) {
    $gl = @()
    foreach($g in $Glob){ if($g){ $gl += ,(Ensure-GlobPrefix $g) } }
    if ($gl.Count -gt 0) {
      $args = @("ls-files","-z","--") + $gl
      $raw  = (& git @args 2>$null); if ($LASTEXITCODE -ne 0) { $raw = "" }
      $tok  = (Join-Out $raw) -split "`0", [System.StringSplitOptions]::RemoveEmptyEntries
      foreach($p in $tok){ if($p -and ($p -notmatch "^(Library/|ops/live/)")){ [void]$targets.Add($p) } }
    }
  }

  $targets = @($targets | Select-Object -Unique)
  if (-not $NoList) {
    Write-Host ("Targets to check ({0}):" -f $targets.Count) -ForegroundColor Cyan
    foreach($t in $targets){ Write-Host ("  - {0}" -f $t) }
  }
  if ($targets.Count -eq 0) { WARN "No changed files to check."; exit 0 }

  # 3) Check each file: blob vs working vs RAW (RAW can be disabled)
  $anyMismatch = $false
  foreach ($rel in $targets) {
    Write-Host ("--- check: {0} ---" -f $rel) -ForegroundColor Cyan
    $args = @('-File', (Join-Path $PSScriptRoot 'check-file-integrity.ps1'),
              '-RepoRoot', $RepoRoot, '-RelPath', $rel,
              '-Owner', $Owner, '-Repo', $Repo, '-Branch', $Branch)
    if ($NoNormalizeWorkingFile) { $args += '-NoNormalizeWorkingFile' }
    if ($SkipRaw) { $args += '-SkipRaw' }
    & pwsh -NoProfile -ExecutionPolicy Bypass @args
    if ($LASTEXITCODE -eq 3) { $anyMismatch = $true }
  }
  if ($anyMismatch) { ERR "One or more files mismatched."; exit 3 }
  OK "All checked files match blob + RAW."; exit 0
}
finally { Pop-Location }
