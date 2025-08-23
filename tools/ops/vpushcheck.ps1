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
  [switch]$SkipRaw,
  [switch]$SkipWorking
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
  function Normalize-ListParam([string[]]$arr){
    if (-not $arr -or $arr.Count -ne 1) { return $arr }
    $s = $arr[0].Trim()
    if ($s.StartsWith("[")) { try { return @((ConvertFrom-Json $s)) } catch { return ,$s } }
    if ($s -match "[,;]")  { return @($s -split "\s*[,;]\s*" | ForEach-Object { $_.Trim("'""") }) }
    return ,$s
  }
  function Ensure-GlobPrefix([string]$p){ if ($p -like ':(glob)*') { $p } else { ':(glob)'+$p } }

  function GitOutZ([string[]]$argv){
    $psi=[System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName='git'
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
    $psi.Arguments = [string]::Join(' ', ($argv | ForEach-Object { if($_ -match '\s|"'){ '"' + ($_ -replace '"','""') + '"' } else { $_ } }))
    $p=[System.Diagnostics.Process]::Start($psi)
    $ms=New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit() | Out-Null
    if($p.ExitCode -ne 0){ return @() }
    $bytes=$ms.ToArray()
    $list = New-Object System.Collections.Generic.List[string]
    $start = 0
    for(;;){
      $idx = [System.Array]::IndexOf($bytes, [byte]0, $start)
      if($idx -lt 0){ $idx = $bytes.Length }
      $len = $idx - $start
      if($len -gt 0){
        $s = [System.Text.Encoding]::UTF8.GetString($bytes, $start, $len)
        [void]$list.Add($s)
      }
      if($idx -ge $bytes.Length){ break }
      $start = $idx + 1
    }
    ,$list.ToArray()
  }

  function Parse-NameStatusTokens([string[]]$tok){
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $tok.Count; ) {
      $code = $tok[$i]; $i++
      if ([string]::IsNullOrWhiteSpace($code)) { continue }
      if ($code -like 'D*') { if ($i -lt $tok.Count) { $i++ }; continue } # skip deletes
      if ($code -like 'R*' -or $code -like 'C*') {
        if ($i + 1 -ge $tok.Count) { break }
        $old = $tok[$i]; $new = $tok[$i+1]; $i += 2; $p = $new
      } else {
        if ($i -ge $tok.Count) { break }
        $p = $tok[$i]; $i++
      }
      if ([string]::IsNullOrWhiteSpace($p)) { continue }
      if ($p -match '^(Library/|ops/live/)') { continue }
      [void]$out.Add($p)
    }
    ,(@($out | Select-Object -Unique))
  }

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

  # Preflight: warn if working tree dirty and we're going to compare Working↔Blob
  if (-not $SkipWorking) {
    $dirty = (& git status --porcelain 2>$null) -ne $null
    # --porcelain emits nothing when clean; treat any output as dirty
    $dirtyText = (& git status --porcelain 2>$null) | Out-String
    if ($dirtyText.Trim().Length -gt 0) {
      WARN "Working tree has local edits; Working↔Blob mismatches are expected. Consider -SkipWorking if you only want Blob↔RAW."
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
      $tokS = GitOutZ @('diff','--name-status','-z','-M','-C',"$Since..$head")
      foreach($p in (Parse-NameStatusTokens $tokS)){ [void]$targets.Add($p) }
    } else {
      $tok1 = GitOutZ @('diff','--name-status','-z','-M','-C',"$preHead..$head")
      foreach($p in (Parse-NameStatusTokens $tok1)){ [void]$targets.Add($p) }
      $tok2 = GitOutZ @('diff-tree','--no-commit-id','--name-status','-z','-r','-M','-C',$preHead)
      foreach($p in (Parse-NameStatusTokens $tok2)){ [void]$targets.Add($p) }
    }
  }

  # Add -Glob matches (tracked files, NUL safe)
  if ($Glob -and $Glob.Count -gt 0) {
    $gl = @()
    foreach($g in $Glob){ if($g){ $gl += ,(Ensure-GlobPrefix $g) } }
    if ($gl.Count -gt 0) {
      $args = @('ls-files','-z','--') + $gl
      $tokG = GitOutZ $args
      foreach($p in $tokG){ if($p -and ($p -notmatch '^(Library/|ops/live/)')){ [void]$targets.Add($p) } }
    }
  }

  $targets = @($targets | Select-Object -Unique)
  if (-not $NoList) {
    Write-Host ("Targets to check ({0}):" -f $targets.Count) -ForegroundColor Cyan
    foreach($t in $targets){ Write-Host ("  - {0}" -f $t) }
  }
  if ($targets.Count -eq 0) { WARN "No changed files to check."; exit 0 }

  # 3) Check each file: blob vs working vs RAW (configurable)
  $anyMismatch = $false
  foreach ($rel in $targets) {
    Write-Host ("--- check: {0} ---" -f $rel) -ForegroundColor Cyan
    $args = @(
      '-File', (Join-Path $PSScriptRoot 'check-file-integrity.ps1'),
      '-RepoRoot', $RepoRoot, '-RelPath', $rel,
      '-Owner', $Owner, '-Repo', $Repo, '-Branch', $Branch
    )
    if ($NoNormalizeWorkingFile) { $args += '-NoNormalizeWorkingFile' }
    if ($SkipRaw)                 { $args += '-SkipRaw' }
    if ($SkipWorking)             { $args += '-SkipWorking' }
    & pwsh -NoProfile -ExecutionPolicy Bypass @args
    if ($LASTEXITCODE -eq 3) { $anyMismatch = $true }
  }

  if ($anyMismatch) { ERR "One or more files mismatched."; exit 3 }
  OK "All checked files match (per selected modes)."; exit 0
}
finally { Pop-Location }
