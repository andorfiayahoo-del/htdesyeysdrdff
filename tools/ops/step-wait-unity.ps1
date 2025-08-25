param(
  [string]$ProjectRoot = (Get-Location).Path,
  [int]$TimeoutSec = 600,
  [string]$StepLabel = "[Step] Wait for Unity compile"
)
$waiter = Join-Path $PSScriptRoot "unity-wait-compile.ps1"
if (-not (Test-Path -LiteralPath $waiter)) { throw "Missing waiter: $waiter" }
Write-Host $StepLabel -ForegroundColor Cyan
Write-Host "→ Alt-Tab to Unity now so it can (re)compile. When you come back here, I will block until it is finished." -ForegroundColor Cyan
[void](Read-Host "Press Enter here after you have focused Unity")
& $waiter -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec
