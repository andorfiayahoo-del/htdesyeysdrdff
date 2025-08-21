param(
  [string]$RepoRoot      = "C:\Users\ander\My project",
  [string]$RouterLogLocal= "$env:USERPROFILE\patch-router.log",
  [string]$ArchLogLocal  = "$env:USERPROFILE\patch-archiver.log",
  [int]   $TailLines     = 2000,
  [switch]$RunOnce
)
$ErrorActionPreference = "Stop"

# --- Quiet git helper (no console noise) ---
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

# --- Helpers ---
$LiveDir = Join-Path $RepoRoot 'ops\live'
New-Item -ItemType Directory -Path $LiveDir -Force | Out-Null
$LiveRouter = Join-Path $LiveDir 'patch-router.log'
$LiveArch   = Join-Path $LiveDir 'patch-archiver.log'
$MetaPath   = Join-Path $LiveDir 'latest.json'

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
  $meta = [ordered]@{
    updatedUtc      = (Get-Date).ToUniversalTime().ToString('o')
    reason          = $reason
    wroteRouter     = $wroteR
    wroteArchiver   = $wroteA
    routerLogFile   = (Test-Path $LiveRouter) ? 'ops/live/patch-router.log'   : $null
    archiverLogFile = (Test-Path $LiveArch)   ? 'ops/live/patch-archiver.log' : $null
  }
  ($meta | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $MetaPath -Encoding UTF8

  Push-Location -LiteralPath $RepoRoot
  try {
    $stage = @()
    if (Test-Path $LiveRouter) { $stage += 'ops/live/patch-router.log' }
    if (Test-Path $LiveArch)   { $stage += 'ops/live/patch-archiver.log' }
    $stage += 'ops/live/latest.json'
    foreach($p in $stage){ Invoke-GitQuiet -GitArgs @('add','-f','--', $p) }
    return $true
  } finally { Pop-Location }
}

function Commit-Push-If-Changes([string]$reason){
  Push-Location -LiteralPath $RepoRoot
  try {
    # Any staged changes?
    & git diff --cached --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
      $stamp = (Get-Date).ToUniversalTime().ToString('o')
      Invoke-GitQuiet -GitArgs @('commit','-m', "ops: update live logs ($reason, $stamp UTC)")
      Invoke-GitQuiet -GitArgs @('-c','rebase.autoStash=true','pull','--rebase','origin','main')
      Invoke-GitQuiet -GitArgs @('push','-u','origin','HEAD:main')
      Write-Host "[OK] Pushed ($reason)." -ForegroundColor Green
    } else {
      # Nothing new; no commit
    }
  } finally { Pop-Location }
}

function Flush([string]$reason){
  if (Snapshot-And-Stage $reason) { Commit-Push-If-Changes $reason }
}

# --- One-shot mode (useful for initial sync) ---
if ($RunOnce) {
  Flush 'run-once'
  return
}

# --- Event-driven mode ---
# Trigger on router lines indicating success, plus any archiver/size change
$rxSuccess = [regex]'APPLY success(?: \((?:reconciled)\))?:\s*patch_\d+\.patch\b'

# Tail router log and act when we see a success line
$routerTail = Start-Job -ScriptBlock {
  param($RouterLogLocal,$rxSuccess,$RepoRoot)
  while (-not (Test-Path -LiteralPath $RouterLogLocal)) { Start-Sleep -Milliseconds 250 }
  Get-Content -LiteralPath $RouterLogLocal -Tail 0 -Wait | ForEach-Object {
    if ($rxSuccess.IsMatch($_)) {
      & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'tools\ops\push-on-apply.ps1') -RunOnce
    }
  }
} -ArgumentList $RouterLogLocal,$rxSuccess,$RepoRoot

# Also watch both log files for any change and debounce ~1.5s
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = [System.IO.Path]::GetDirectoryName($RouterLogLocal)
$fsw.Filter = 'patch-*.log'
$fsw.IncludeSubdirectories = $false
$fsw.EnableRaisingEvents = $true
$fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'

$script:lastFire = Get-Date 0
Register-ObjectEvent -InputObject $fsw -EventName Changed -Action {
  if ((Get-Date) - $script:lastFire -lt [TimeSpan]::FromMilliseconds(1500)) { return }
  $script:lastFire = Get-Date
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'tools\ops\push-on-apply.ps1') -RunOnce
} | Out-Null

# Initial sync so repo has live files immediately
Flush 'initial-sync'

Write-Host "[RUNNING] push-on-apply: watching logs & pushing on change…" -ForegroundColor Cyan
while ($true) { Start-Sleep -Seconds 3600 }
