param([string]$ProjectRoot = (Get-Location).Path, [int]$TimeoutSec = 900, [switch]$RequireBusy)
$ErrorActionPreference = "Stop"
$waiter = Join-Path $PSScriptRoot "unity-wait-compile.ps1"
if (-not (Test-Path -LiteralPath $waiter)) { throw "Missing waiter: $waiter" }
Add-Type -Namespace Fgw -Name Win32 -MemberDefinition @("
  [DllImport(""user32.dll"")] public static extern IntPtr GetForegroundWindow();
  [DllImport(""user32.dll"")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
")
Write-Host "[Step] Focus Unity, then wait for compile (no keypress)" -ForegroundColor Cyan
Write-Host " — bring Unity to the front; I will detect focus automatically." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds([Math]::Min($TimeoutSec, 120))
while ($true) {
  $h = [Fgw.Win32]::GetForegroundWindow()
  if ($h -ne [IntPtr]::Zero) {
    [uint32]$ppid = 0; [void][Fgw.Win32]::GetWindowThreadProcessId($h, [ref]$ppid)
    try {
      if ($ppid -ne 0) { $p = Get-Process -Id $ppid -ErrorAction Stop; if ($p.ProcessName -like "Unity*") { break } }
    } catch {}
  }
  if ((Get-Date) -gt $deadline) { Write-Host "[unity-focus] Timed out waiting for Unity focus (continuing anyway)" -ForegroundColor Yellow; break }
  Start-Sleep -Milliseconds 120
}
Write-Host "[unity-focus] Unity focused — waiting for compile completion..." -ForegroundColor Cyan
& $waiter -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec -RequireBusy:$RequireBusy.IsPresent