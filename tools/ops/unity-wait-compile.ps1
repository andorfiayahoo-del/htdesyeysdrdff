param(
  [Parameter(Mandatory)][string]$ProjectRoot,
  [int]$TimeoutSec = 300,
  [string]$UnityExe,
  [switch]$EmitPing
)
$ErrorActionPreference = "Stop"
$Sentinel = Join-Path $ProjectRoot "ops\live\unity-compile.json"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
function Get-CompileState {
  if (-not (Test-Path -LiteralPath $Sentinel)) { return @{ found=$false } }
  try {
    $j = Get-Content -LiteralPath $Sentinel -Raw | ConvertFrom-Json
    return @{ found=$true; isCompiling=[bool]$j.isCompiling; isUpdating=[bool]$j.isUpdating; stamp=$j.timestamp }
  } catch { return @{ found=$true; isCompiling=$true; isUpdating=$true } }
}
if ($EmitPing -and $UnityExe) {
  Write-Host "[unity-wait-compile] Emitting ping via Unity.exe" -ForegroundColor Cyan
  & $UnityExe -projectPath $ProjectRoot -batchmode -nographics -quit -executeMethod Ops.CompileSentinel.EmitOnce | Out-Null
}
while ($true) {
  if ((Get-Date) -gt $deadline) { throw "Timeout waiting for sentinel at $Sentinel" }
  $s = Get-CompileState
  if ($s.found) { break }
  Write-Host "[unity-wait-compile] Sentinel not found yet, retrying..." -ForegroundColor DarkGray
  Start-Sleep -Seconds 1
}
while ($true) {
  if ((Get-Date) -gt $deadline) { throw "Timeout waiting for Unity to finish compiling/updating" }
  $s = Get-CompileState
  if ($s.found -and -not $s.isCompiling -and -not $s.isUpdating) {
    Write-Host "[unity-wait-compile] Done: isCompiling=$($s.isCompiling) isUpdating=$($s.isUpdating)" -ForegroundColor Green
    break
  }
  Start-Sleep -Milliseconds 500
}
exit 0
