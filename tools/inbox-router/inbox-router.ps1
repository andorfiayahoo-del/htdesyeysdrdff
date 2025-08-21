# inbox-router.ps1  v1.7.12
# - Push AFTER Unity compile for C# patches; push immediately for non-C# patches
# - Same safety features as v1.7.10 (safe path resolve, lint, reconcile, verify new .cs, single-instance)

param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----- Settings (defaults; adjust if needed) -----
$RepoRoot   = 'C:\Users\ander\My project'
$Downloads  = "$env:USERPROFILE\Downloads"
$LogPath    = "$env:USERPROFILE\patch-router.log"
$DebounceMs = 1500
$SettleMs   = 1200
$PollMs     = 500

function Write-Log([string]$msg, [string]$level='') {
  try {
    # Demote harmless transport chatter to yellow notes
    if ($msg -match '^GIT exception:\s*(From|To)\s') {
      $msg = $msg -replace '^GIT exception:', 'GIT note:'
      $level = 'Y'
    } elseif ($msg -match '^GIT exception:' -and $msg -notmatch '(error:|fatal:|denied|permission)') {
      $msg = $msg -replace '^GIT exception:', 'GIT note:'
      if ($level -eq '' -or $level -eq 'R') { $level = 'Y' }
    }

    $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line = "[$ts] $msg"
    Add-Content -LiteralPath $LogPath -Value $line
    switch ($level) {
      'G' { Write-Host $line -ForegroundColor Green; break }
      'Y' { Write-Host $line -ForegroundColor Yellow; break }
      'R' { Write-Host $line -ForegroundColor Red; break }
      default { Write-Host $line }
    }
  } catch {}
}

# Single-instance guard
try {
  $thisPath = $MyInvocation.MyCommand.Path
  $others = Get-CimInstance Win32_Process |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match [regex]::Escape($thisPath) }
  if ($others) {
    $pids = ($others | Select-Object -Expand ProcessId) -join ','
    Write-Log ("ABORT already-running pids={0}" -f $pids) 'R'
    return
  }
} catch {}

# Safe script path resolve
$scriptPath = $null
if ($PSCommandPath) { $scriptPath = $PSCommandPath }
if (-not $scriptPath) {
  try { $scriptPath = $MyInvocation.MyCommand.Path } catch { $scriptPath = '<unknown>' }
}

Write-Log ("BOOT who={0}\{1} pid={2} pwsh={3} cwd={4}" -f $env:COMPUTERNAME,$env:USERNAME,$PID,$PSVersionTable.PSVersion,(Get-Location))
Write-Log ("SCRIPT version=v1.7.12 path={0}" -f $scriptPath)

# Repo presence
if (-not (Test-Path -LiteralPath $RepoRoot))  { Write-Log ("ERROR missing repo path: {0}" -f $RepoRoot) 'R'; return }
if (-not (Test-Path -LiteralPath $Downloads)) { Write-Log ("ERROR missing Downloads path: {0}" -f $Downloads) 'R'; return }
try {
  Push-Location -LiteralPath $RepoRoot
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { Write-Log ("ERROR not a git repo: {0}" -f $RepoRoot) 'R'; return }
} finally { Pop-Location }

function Invoke-Git([string[]]$gitArgs) {
  try {
    Push-Location -LiteralPath $RepoRoot
    & git @gitArgs 2>&1 | ForEach-Object { Write-Log ("GIT " + $_) }
    return $LASTEXITCODE
  } catch { Write-Log ("GIT exception: " + $_.Exception.Message) 'R'; return 1 }
  finally { Pop-Location }
}

function Get-CurrentBranch() {
  try {
    Push-Location -LiteralPath $RepoRoot
    $out = & git symbolic-ref --quiet --short HEAD 2>&1
    if ($LASTEXITCODE -eq 0) { return ($out | Select-Object -First 1).Trim() }
    else { return $null } # detached
  } catch { return $null }
  finally { Pop-Location }
}

function Ensure-BranchMain() {
  $cur = Get-CurrentBranch
  $detached = (-not $cur)
  if (-not $detached -and $cur -eq 'main') { return $true }

  $curDisplay = '<detached>'; if ($cur) { $curDisplay = $cur }
  Write-Log ("ENSURE main: cur='{0}' detached={1}" -f $curDisplay, $detached) 'Y'

  [void](Invoke-Git @('fetch','--prune','origin'))
  $haveMain = ((Invoke-Git @('rev-parse','--verify','main')) -eq 0)
  if (-not $haveMain) { [void](Invoke-Git @('branch','-f','main','HEAD')) }

  $sw = Invoke-Git @('switch','-f','main')
  if ($sw -ne 0) {
    $co = Invoke-Git @('checkout','-f','main')
    if ($co -ne 0) { Write-Log "ENSURE main: failed to switch/checkout main" 'R'; return $false }
  }
  if (Invoke-Git @('-c','rebase.autoStash=true','pull','--rebase','origin','main')) {
    Write-Log "ENSURE main: pull --rebase failed" 'Y'
  }
  Write-Log "ENSURE main: now on 'main' (up-to-date or best-effort)" 'Y'
  return $true
}

# ---- Patch parsing / linter ----
function Parse-PatchInfo([string]$patchPath) {
  $text  = Get-Content -LiteralPath $patchPath -Raw -Encoding UTF8
  $lines = $text -split "`r?`n"

  $info = @{}; $file=$null; $inHunk=$false; $isNewForCurrent=$false
  foreach ($ln in $lines) {
    if ($ln -like 'diff --git *') { $file=$null; $inHunk=$false; $isNewForCurrent=$false; continue }
    if ($ln -like 'new file mode *') { $isNewForCurrent=$true; continue }
    if ($ln -like '+++ b/*') {
      $candidate = $ln.Substring(6); $file = $candidate
      if (-not $info.ContainsKey($file)) {
        $isCs = ($file -like '*.cs')
        $info[$file] = @{ IsCs = $isCs; IsNew = $isNewForCurrent; AddedLines = @() }
      } else { if ($isNewForCurrent) { $info[$file]['IsNew'] = $true } }
      continue
    }
    if ($ln -like '@@*@@*') { $inHunk = $true; continue }
    if ($inHunk -and $file -ne $null -and $ln.StartsWith('+') -and -not $ln.StartsWith('+++')) {
      $info[$file]['AddedLines'] += $ln.Substring(1)
    }
  }
  return $info
}

function Lint-CsAdded([string]$file,[string[]]$addedLines) {
  if (-not $addedLines -or $addedLines.Count -eq 0) { return $true }
  $txt = [string]::Join("`n", $addedLines)
  $ifs    = [regex]::Matches($txt, '^\s*#if\s+UNITY_EDITOR', 'Multiline').Count
  $endifs = [regex]::Matches($txt, '^\s*#endif\s*$', 'Multiline').Count
  if ($ifs -gt 0 -and $endifs -eq 0) { Write-Log ("LINT fail: {0} has #if UNITY_EDITOR without #endif" -f $file) 'R'; return $false }
  $nonEmpty = $addedLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
  if ($nonEmpty.Count -gt 0) {
    $first = $nonEmpty[0]; $last = $nonEmpty[$nonEmpty.Count-1]
    if ($first -match '^\s*#if\s+UNITY_EDITOR' -and $last -notmatch '^\s*#endif\s*$') {
      Write-Log ("LINT fail: {0} begins with #if UNITY_EDITOR but last added line is not #endif" -f $file) 'R'
      return $false
    }
  }
  $opens = ([regex]::Matches($txt, '\{')).Count; $closes = ([regex]::Matches($txt, '\}')).Count
  if ($opens -ne $closes) { Write-Log ("LINT fail: {0} unbalanced braces ({1} vs {2})" -f $file, $opens, $closes) 'R'; return $false }
  Write-Log ("LINT ok: {0} (#if={1}, #endif={2}, braces ok)" -f $file, $ifs, $endifs)
  return $true
}
function Lint-Patch([hashtable]$info) {
  foreach ($k in $info.Keys) {
    $v = $info[$k]
    if ($v['IsCs']) {
      if (-not (Lint-CsAdded $k $v['AddedLines'])) { return $false }
    }
  }
  return $true
}

# ---- Post-apply verification / fix for NEW .cs files ----
function Verify-And-Fix-NewCs([hashtable]$info) {
  foreach ($k in $info.Keys) {
    $v = $info[$k]
    if (-not $v['IsCs']) { continue }
    if (-not $v['IsNew']) { continue }

    $rel = $k -replace '/', ''
    $full = Join-Path $RepoRoot $rel
    $expected = [string]::Join("`r`n", $v['AddedLines']) + "`r`n"

    $needEndIf = $false
    foreach ($line in $v['AddedLines']) { if ($line -match '^\s*#if\s+UNITY_EDITOR') { $needEndIf = $true; break } }

    $shouldHaveEndIf = $false
    foreach ($line in $v['AddedLines']) { if ($line -match '^\s*#endif\s*$') { $shouldHaveEndIf = $true; break } }

    $repair = $false
    $actual = ''
    if (Test-Path -LiteralPath $full) {
      try { $actual = Get-Content -LiteralPath $full -Raw -Encoding UTF8 } catch {}
    }

    $actualLines = @()
    if ($actual -ne '') { $actualLines = $actual -split "`r?`n" }

    if ($needEndIf -and -not $shouldHaveEndIf) {
      $repair = $true
      Write-Log ("VERIFY WARN: patch for {0} lacks #endif in added lines" -f $k) 'Y'
    } else {
      if ($actualLines.Count -lt $v['AddedLines'].Count) { $repair = $true }
      if ($needEndIf) {
        $hasEndIfOnDisk = $false
        foreach ($line in $actualLines) { if ($line -match '^\s*#endif\s*$') { $hasEndIfOnDisk = $true; break } }
        if (-not $hasEndIfOnDisk) { $repair = $true }
      }
    }

    if ($repair) {
      try {
        $dir = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force *> $null }
        Set-Content -LiteralPath $full -Value $expected -Encoding UTF8
        Write-Log ("FIXUP wrote expected content for {0} (from patch added lines)" -f $k) 'Y'
      } catch {
        Write-Log ("FIXUP failed to write ${k}: " + $_.Exception.Message) 'R'
        return $false
      }
    }
  }
  return $true
}

# ---- Ensure #if/#endif balanced on disk for ANY .cs file ----
function Ensure-BalancedUnityIf([string]$fullPath) {
  if (-not (Test-Path -LiteralPath $fullPath)) { return }
  try {
    $src = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    $ifs    = [regex]::Matches($src, '^\s*#if\s+UNITY_EDITOR', 'Multiline').Count
    $endifs = [regex]::Matches($src, '^\s*#endif\s*$', 'Multiline').Count
    Write-Log ("POSTCHECK {0}: #if={1} #endif={2}" -f $fullPath, $ifs, $endifs) 'Y'
    if ($ifs -gt $endifs) {
      $toAdd = $ifs - $endifs
      $append = ''
      for ($i=0; $i -lt $toAdd; $i++) { $append += "`r`n#endif" }
      Add-Content -LiteralPath $fullPath -Value $append -Encoding UTF8
      Write-Log ("FIXUP appended {0} '#endif' to {1}" -f $toAdd, $fullPath) 'Y'
    }
  } catch {
    Write-Log ("POSTCHECK failed for {0}: {1}" -f $fullPath, $_.Exception.Message) 'R'
  }
}

function Should-WaitForCompile([hashtable]$info) {
  foreach ($k in $info.Keys) { if ($info[$k]['IsCs']) { return $true } }
  return $false
}

# ---- Unity compile wait (no timeout) ----
function Wait-ForUnityCompile([datetime]$sinceUtc) {
  $stamp = Join-Path $RepoRoot 'Assets\InboxPatches\CompileDone.stamp'
  Write-Log ("UNITY wait: request={0:o} (waiting until CompileDone.stamp >= request)" -f $sinceUtc) 'Y'
  while ($true) {
    try {
      if (Test-Path -LiteralPath $stamp) {
        $w = (Get-Item -LiteralPath $stamp).LastWriteTimeUtc
        if ($w -ge $sinceUtc) { Write-Log ("UNITY compiled: {0:o} (>= request)" -f $w) 'G'; break }
      }
    } catch {}
    Start-Sleep -Milliseconds 500
  }
}

# ---- Reconcile for "new-file" patches if files already exist ----
function Reconcile-NewFiles([hashtable]$info,[string]$patchName) {
  $anyWrites = $false
  $allNew = $true
  foreach ($k in $info.Keys) { if (-not $info[$k]['IsNew']) { $allNew = $false; break } }
  if (-not $allNew) { return $false }

  foreach ($k in $info.Keys) {
    $rel = ($k -replace '/', '')
    $full = Join-Path $RepoRoot $rel
    $expected = [string]::Join("`r`n", $info[$k]['AddedLines']) + "`r`n"

    if (-not (Test-Path -LiteralPath $full)) {
      try {
        $dir = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force *> $null }
        Set-Content -LiteralPath $full -Value $expected -Encoding UTF8
        Write-Log ("RECONCILE wrote missing file {0}" -f $k) 'Y'
        $anyWrites = $true
      } catch {
        Write-Log ("RECONCILE failed to write ${k}: " + $_.Exception.Message) 'R'
        return $false
      }
    } else {
      $actual = ''
      try { $actual = Get-Content -LiteralPath $full -Raw -Encoding UTF8 } catch {}
      if ($actual -ne $expected) {
        try {
          Set-Content -LiteralPath $full -Value $expected -Encoding UTF8
          Write-Log ("RECONCILE replaced existing {0} with expected content" -f $k) 'Y'
          $anyWrites = $true
        } catch {
          Write-Log ("RECONCILE failed to replace ${k}: " + $_.Exception.Message) 'R'
          return $false
        }
      } else {
        Write-Log ("RECONCILE skip: {0} already matches expected content" -f $k)
      }
    }

    if ($info[$k]['IsCs']) {
      $full = Join-Path $RepoRoot (($k -replace '/', ''))
      if (Test-Path -LiteralPath $full) {
        try {
          $src = Get-Content -LiteralPath $full -Raw -Encoding UTF8
          $ifs = [regex]::Matches($src, '^\s*#if\s+UNITY_EDITOR', 'Multiline').Count
          $endifs = [regex]::Matches($src, '^\s*#endif\s*$', 'Multiline').Count
          if ($ifs -gt $endifs) { Add-Content -LiteralPath $full -Value "`r`n#endif" -Encoding UTF8 }
        } catch {}
      }
    }
  }

  if ($anyWrites) {
    if (Invoke-Git @('add','-A')) { Write-Log ("RECONCILE stage-failed: {0}" -f $patchName) 'R'; return $false }
    $msg = "inbox: reconcile " + $patchName
    if (Invoke-Git @('commit','-m',$msg)) { Write-Log ("RECONCILE commit-failed: {0}" -f $patchName) 'R'; return $false }
    if (Invoke-Git @('-c','rebase.autoStash=true','pull','--rebase','origin','main')) { Write-Log ("RECONCILE pull-warning: {0}" -f $patchName) 'Y' }

    $since = (Get-Date).ToUniversalTime()
    if (Should-WaitForCompile $info) { Wait-ForUnityCompile $since } else { Write-Log "UNITY skip: no .cs changes in this patch" 'Y' }

    if (Invoke-Git @('push','-u','origin','HEAD:main')) { Write-Log ("RECONCILE push-warning: {0}" -f $patchName) 'Y' }
  } else {
    Write-Log ("RECONCILE result: all files already present and identical for {0}" -f $patchName)
  }

  return $true
}
# ---- Move helper ----
# ---- Main apply flow ----
function Apply-Patch([string]$fullPath) {
  $name = Split-Path -Leaf $fullPath
  Write-Log ("APPLY start: {0}" -f $name)
  try {
    if (-not (Test-Path -LiteralPath $fullPath)) { Write-Log ("APPLY missing: {0}" -f $name) 'R'; return }

    if (-not (Ensure-BranchMain)) { Write-Log "APPLY aborted: could not ensure 'main'" 'R'; return }

    $pi = Parse-PatchInfo $fullPath
    if (-not (Lint-Patch $pi)) { Write-Log ("APPLY lint-failed: {0}" -f $name) 'R'; return }

    $check = Invoke-Git @('-c','core.safecrlf=false','apply','--check','--whitespace=nowarn',$fullPath)
    if ($check -ne 0) {
      if (Reconcile-NewFiles $pi $name) {
        foreach ($k in $pi.Keys) { if ($pi[$k]['IsCs']) {
          $full = Join-Path $RepoRoot (($k -replace '/', ''))
          Ensure-BalancedUnityIf $full
        }}
        $since = (Get-Date).ToUniversalTime()
        if (Should-WaitForCompile $pi) { Wait-ForUnityCompile $since } else { Write-Log "UNITY skip: no .cs changes in this patch" 'Y' }
        Write-Log ("APPLY success (reconciled): {0}" -f $name) 'G'
        Move-AppliedPatch $fullPath $name
        return
      }

      $rev = Invoke-Git @('-c','core.safecrlf=false','apply','-R','--check','--whitespace=nowarn',$fullPath)
      if ($rev -eq 0) { Write-Log ("APPLY already-applied: {0}" -f $name) 'Y'; return }

      Write-Log ("APPLY check-failed: {0}" -f $name) 'R'
      return
    }

    if (Invoke-Git @('-c','core.safecrlf=false','apply','--whitespace=nowarn',$fullPath)) { Write-Log ("APPLY failed: {0}" -f $name) 'R'; return }

    if (-not (Verify-And-Fix-NewCs $pi)) { Write-Log ("APPLY verify-failed: {0}" -f $name) 'R'; return }

    foreach ($k in $pi.Keys) {
      if ($pi[$k]['IsCs']) {
        $full = Join-Path $RepoRoot (($k -replace '/', ''))
        Ensure-BalancedUnityIf $full
      }
    }

    if (Invoke-Git @('add','-A')) { Write-Log ("APPLY stage-failed: {0}" -f $name) 'R'; return }
    $msg = "inbox: apply " + $name
    if (Invoke-Git @('commit','-m',$msg)) { Write-Log ("APPLY commit-failed: {0}" -f $name) 'R'; return }
    if (Invoke-Git @('-c','rebase.autoStash=true','pull','--rebase','origin','main')) { Write-Log ("APPLY pull-warning: {0}" -f $name) 'Y' }

    $since = (Get-Date).ToUniversalTime()
    if (Should-WaitForCompile $pi) { Wait-ForUnityCompile $since } else { Write-Log "UNITY skip: no .cs changes in this patch" 'Y' }
    if (Invoke-Git @('push','-u','origin','HEAD:main')) { Write-Log ("APPLY push-warning: {0}" -f $name) 'Y' }

    Write-Log ("APPLY success: {0}" -f $name) 'G'
    Move-AppliedPatch $fullPath $name
  }
  catch { Write-Log ("APPLY exception: " + $_.Exception.Message) 'R' }
}

# ---- Watch loop ----
$processed = @{}  # path -> ticks
Write-Log ("WATCH polling: {0} (*.patch) debounce={1} settle={2} poll={3}" -f $Downloads,$DebounceMs,$SettleMs,$PollMs)
while ($true) {
  try {
    $files = Get-ChildItem -LiteralPath $Downloads -Filter '*.patch' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
      $path  = $f.FullName
      $ticks = $f.LastWriteTimeUtc.Ticks
      if ($processed.ContainsKey($path) -and $processed[$path] -eq $ticks) { continue }
      $ageMs = [int]((New-TimeSpan -Start $f.LastWriteTimeUtc -End (Get-Date).ToUniversalTime()).TotalMilliseconds)
      if ($ageMs -lt $DebounceMs) { continue }

      try {
        $a = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds $SettleMs
        $b = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $a -or -not $b -or ($a.Length -ne $b.Length -or $a.LastWriteTimeUtc -ne $b.LastWriteTimeUtc)) { continue }
      } catch { continue }

      Write-Log ("READY detected: '{0}' size={1} lastWriteUtc={2:o}" -f $path,$f.Length,$f.LastWriteTimeUtc)
      Apply-Patch $path
      $processed[$path] = $ticks
    }
  } catch { Write-Log ("LOOP exception: " + $_.Exception.Message) 'R' }
  Start-Sleep -Milliseconds $PollMs
}







# ---- Archiver stub (safe) ----
if (-not (Get-Command -Name Move-AppliedPatch -ErrorAction SilentlyContinue)) {
  function Move-AppliedPatch([string]$fullPath,[string]$name) {
    try {
      if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("ARCHIVE note: external archiver handles '{0}'" -f $name) 'Y'
      } else {
        Write-Host ("[ARCHIVE] external archiver handles '{0}'" -f $name)
      }
    } catch { }
  }
}
