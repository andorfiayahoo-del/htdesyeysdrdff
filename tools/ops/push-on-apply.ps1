param(
  [string]$RepoRoot       = "C:\Users\ander\My project",
  [string]$RouterLogLocal = "$env:USERPROFILE\patch-router.log",
  [string]$ArchLogLocal   = "$env:USERPROFILE\patch-archiver.log",
  [int]   $TailLines      = 2000,
  [switch]$RunOnce
)
$ErrorActionPreference = 'Stop'

# --- quiet git helper (fully silent) ---
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
$Cooldown    = Join-Path $LiveDir  '.cooldown'
New-Item -ItemType Directory -Path $LiveDir -Force | Out-Null

function Cooldown-Ok([int]$ms = 1500){
  try {
    if (Test-Path -LiteralPath $Cooldown) {
      $age = (Get-Date) - (Get-Item -LiteralPath $Cooldown).LastWriteTime
      if ($age.TotalMilliseconds -lt $ms) { return $false }
      (Get-Item -LiteralPath $Cooldown).LastWriteTime = Get-Date
      return $true
    } else {
      Set-Content -LiteralPath $Cooldown -Value '' -Encoding ascii
      return $true
    }
  } catch { return $true }
}

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

# --- One-shot mode (spawned by the watcher; guarded) ---
if ($RunOnce) {
  if (-not (Cooldown-Ok 1500)) { return }
  Flush 'run-once'
  return
}

# --- Event-driven mode: watch both logs and spawn -RunOnce on change ---
$self = $MyInvocation.MyCommand.Path
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Ensure initial snapshot exists in the repo
Flush 'initial-sync'

# Watch for Created + Changed on patch-*.log in user profile
$dir = Split-Path -Parent $RouterLogLocal
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $dir
$fsw.Filter = 'patch-*.log'
$fsw.IncludeSubdirectories = $false
$fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'
$fsw.EnableRaisingEvents = $true

$action = {
  try {
    Start-Process -FilePath $using:psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$using:self,'-RunOnce') -WindowStyle Hidden
  } catch {}
}
Register-ObjectEvent -InputObject $fsw -EventName Created -Action $action | Out-Null
Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $action | Out-Null

Write-Host '[RUNNING] push-on-apply: event-driven (-RunOnce + cooldown).' -ForegroundColor Cyan
while ($true) { Start-Sleep -Seconds 3600 }
