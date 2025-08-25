param(
  [Parameter(Mandatory)][string]$ProjectRoot,
  [int]$TimeoutSec = 300,
  [switch]$RequireBusy
)
$ErrorActionPreference = "Stop"
$Sentinel = Join-Path $ProjectRoot "ops\live\unity-compile.json"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
function Read-State {
  if (-not (Test-Path -LiteralPath $Sentinel)) { return @{ found=$false } }
  try {
    $j = Get-Content -LiteralPath $Sentinel -Raw | ConvertFrom-Json
    return @{ found=$true; isCompiling=[bool]$j.isCompiling; isUpdating=[bool]$j.isUpdating; stamp=$j.timestamp }
  } catch { return @{ found=$true; isCompiling=$true; isUpdating=$true } }
}
while (-not (Test-Path -LiteralPath $Sentinel)) {
  if ((Get-Date) -gt $deadline) { throw "Timeout: sentinel not found at $Sentinel" }
  Start-Sleep -Milliseconds 200
}
$seenBusy = $false
$stableIdle = 0
while ($true) {
  if ((Get-Date) -gt $deadline) { throw "Timeout: Unity did not reach idle state" }
  $s = Read-State
  if ($s.found) {
    if ($s.isCompiling -or $s.isUpdating) { $seenBusy = $true; $stableIdle = 0 }
    else { if (-not $RequireBusy -or $seenBusy) { $stableIdle++ } }
  }
  if ($stableIdle -ge 3) { break }
  Start-Sleep -Milliseconds 200
}
Write-Host "[unity-wait-compile] Idle after busy=$seenBusy" -ForegroundColor Green
exit 0