param(
  [string]$RepoRoot       = "C:\Users\ander\My project",
  [string]$RouterLogLocal = "$env:USERPROFILE\patch-router.log",
  [string]$ArchLogLocal   = "$env:USERPROFILE\patch-archiver.log",
  [int]   $TailLines      = 2000,
  [switch]$RunOnce
)
$ErrorActionPreference = 'Stop'

# --- quiet git helper (no console noise) ---
function Invoke-GitQuiet { param([string[]]$GitArgs)
  if (-not $GitArgs -or $GitArgs.Count -eq 0) { return }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName               = 'git'
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow         = $true
  $psi.Arguments = [string]::Join(' ', ($GitArgs | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + ($_ -replace '"','""') + '"' } else { $_ }
  }))
  $p = [System.Diagnostics.Process]::Start($psi)
  $null = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit() | Out-Null
}

# --- paths in repo for "live" view ---
$LiveDir     = Join-Path $RepoRoot 'ops\live'
$LiveRouter  = Join-Path $LiveDir  'patch-router.log'
$LiveArch    = Join-Path $LiveDir  'patch-archiver.log'
$MetaPath    = Join-Path $LiveDir  'latest.json'
New-Item -ItemType Directory -Path $LiveDir -Force | Out-Null

function Write-IfExists([string]$src,[string]$dst,[int]$tail){
  if (Test-Path -LiteralPath $src){
    try {
      $lines = Get-Content -LiteralPath $src -Tail $tail -ErrorAction Stop
      $lines | Set-Content -LiteralPath $dst -Encoding UTF8
      return $true
    } catch { return $false }
  }
  return $false
}

function Snapshot-And-Stage([string]$reason){
  $wroteR = Write-IfExists $RouterLogLocal $LiveRouter $TailLines
  $wroteA = Write-IfExists $ArchLogLocal   $LiveArch   $TailLines

  $routerFile   = $null
  $archiverFile = $null
  if (Test-Path -LiteralPath $LiveRouter) { $routerFile   = 'ops/live/patch-router.log' }
  if (Test-Path -LiteralPath $LiveArch)   { $archiverFile = 'ops/live/patch-archiver.log' }

  $meta = [ordered]@{
    updatedUtc      = (Get-Date).ToUniversalTime().ToString('o')
    reason          = $reason
    wroteRouter     = $wroteR
    wroteArchiver   = $wroteA
    routerLogFile   = $routerFile
    archiverLogFile = $archiverFile
  }
  ($meta | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $MetaPath -Encoding UTF8

  Push-Location -LiteralPath $RepoRoot
  try {
    $stage = @()
    if ($routerFile)   { $stage += $routerFile }
    if ($archiverFile) { $stage += $archiverFile }
    $stage += 'ops/live/latest.json'
    foreach($p in $stage){ Invoke-GitQuiet -GitArgs @('add','-f','--', $p) }
    return $true
  } finally { Pop-Location }
}

function Commit-Push-If-Changes([string]$reason){
  Push-Location -LiteralPath $RepoRoot
  try {
    & git diff --cached --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
      $stamp = (Get-Date).ToUniversalTime().ToString('o')
      Invoke-GitQuiet -GitArgs @('commit','-m', "ops: update live logs ($reason, $stamp UTC)")
      Invoke-GitQuiet -GitArgs @('-c','rebase.autoStash=true','pull','--rebase','origin','main')
      Invoke-GitQuiet -GitArgs @('push','-u','origin','HEAD:main')
      Write-Host "[OK] Pushed ($reason)." -ForegroundColor Green
    }
  } finally { Pop-Location }
}

function Flush([string]$reason){
  if (Snapshot-And-Stage $reason) { Commit-Push-If-Changes $reason }
}

# One-shot mode for manual triggers
if ($RunOnce) { Flush 'run-once'; return }

# --- event wiring (no polling) ---
$rxSuccess  = [regex]'APPLY success(?: \((?:reconciled)\))?:\s*patch_\d+\.patch\b'
$script:pendingReason = $null

# Debounce timer that fires after 1.2s from the last change
$script:debounce = New-Object System.Timers.Timer 1200
$script:debounce.AutoReset = $false
Register-ObjectEvent -InputObject $script:debounce -EventName Elapsed -SourceIdentifier 'DebouncedFlush' -Action {
  try {
    $r = $script:pendingReason
    $script:pendingReason = $null
    if (-not $r) { $r = 'debounced-change' }
    Flush $r
  } catch {}
} | Out-Null

# FileSystemWatcher for both logs
$dir = Split-Path -Parent $RouterLogLocal
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $dir
$fsw.Filter = 'patch-*.log'
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
$fsw.EnableRaisingEvents = $true

Register-ObjectEvent -InputObject $fsw -EventName Changed -SourceIdentifier 'LogChanged' -Action {
  try {
    $path = $Event.SourceEventArgs.FullPath
    $reason = 'change'
    if ($path -like '*patch-router.log') {
      try {
        $tail = Get-Content -LiteralPath $path -Tail 80
        foreach ($ln in $tail) {
          if ($ln -match 'APPLY success(?: \((?:reconciled)\))?:\s*patch_\d+\.patch\b') {
            $reason = 'apply-success'; break
          }
        }
      } catch {}
    }
    # escalate reason if a stronger one arrives before debounce fires
    if ($script:pendingReason -ne 'apply-success') { $script:pendingReason = $reason }
    $script:debounce.Stop(); $script:debounce.Start()
  } catch {}
} | Out-Null

# Initial sync then idle
Flush 'initial-sync'
Write-Host '[RUNNING] push-on-apply: watching logs & pushing on change.' -ForegroundColor Cyan
while ($true) { Start-Sleep -Seconds 3600 }
