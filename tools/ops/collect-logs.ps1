param(
  [string]$RepoRoot        = "C:\Users\ander\My project",
  [string]$RouterLogLocal  = "$env:USERPROFILE\patch-router.log",
  [string]$ArchLogLocal    = "$env:USERPROFILE\patch-archiver.log",
  [int]   $TailLines       = 2000,
  [switch]$InstallScheduledTask
)
$ErrorActionPreference = "Stop"
$LogRepoDir = Join-Path $RepoRoot "ops\logs"
New-Item -ItemType Directory -Path $LogRepoDir -Force | Out-Null

function Write-IfExists([string]$src, [string]$dst){
  if (Test-Path -LiteralPath $src){
    try {
      $lines = Get-Content -LiteralPath $src -Tail $TailLines -ErrorAction Stop
      $lines | Set-Content -LiteralPath $dst -Encoding UTF8
      return $true
    } catch { return $false }
  }
  return $false
}

$tsUtc    = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssZ")
$routerOut= Join-Path $LogRepoDir ("patch-router_{0}.log"   -f $tsUtc)
$archOut  = Join-Path $LogRepoDir ("patch-archiver_{0}.log" -f $tsUtc)

$wroteRouter = Write-IfExists -src $RouterLogLocal -dst $routerOut
$wroteArch   = Write-IfExists -src $ArchLogLocal   -dst $archOut

$latestPath = Join-Path $LogRepoDir "latest.json"
$meta = [ordered]@{
  updatedUtc      = (Get-Date).ToUniversalTime().ToString('o')
  wroteRouter     = $wroteRouter
  wroteArchiver   = $wroteArch
  routerLogFile   = if ($wroteRouter) { Split-Path -Leaf $routerOut } else { $null }
  archiverLogFile = if ($wroteArch)   { Split-Path -Leaf $archOut }   else { $null }
}
($meta | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $latestPath -Encoding UTF8

Set-Location -LiteralPath $RepoRoot
& git add -- "ops/logs/*" *> $null
& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  $stamp = (Get-Date).ToUniversalTime().ToString("o")
  & git commit -m "ops: ingest logs ($stamp UTC)" *> $null
  & git -c rebase.autoStash=true pull --rebase origin main *> $null
  & git push -u origin HEAD:main *> $null
  Write-Host "[OK] Logs committed & pushed." -ForegroundColor Green
} else {
  Write-Host "[SKIP] No log changes to commit." -ForegroundColor Yellow
}

if ($InstallScheduledTask) {
  $taskName = "RepoLogCollector"
  $psExe    = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $taskCmd  = "$psExe -NoProfile -ExecutionPolicy Bypass -File `"$RepoRoot\tools\ops\collect-logs.ps1`""
  try { schtasks /Delete /TN $taskName /F *> $null } catch {}
  schtasks /Create /TN $taskName /TR "$taskCmd" /SC MINUTE /MO 5 /F | Out-Null
  Write-Host "[OK] Scheduled Task '$taskName' installed (every 5 minutes)." -ForegroundColor Green
}
