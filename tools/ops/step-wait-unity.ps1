param(
  [string]$ProjectRoot = (Get-Location).Path,
  [int]$TimeoutSec = 900,
  [string]$StepLabel = "[Step] Focus Unity, then wait for compile (no keypress)"
)
$ErrorActionPreference = "Stop"
$waiter = Join-Path $PSScriptRoot "unity-wait-compile.ps1"
if (-not (Test-Path -LiteralPath $waiter)) { throw "Missing waiter: $waiter" }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Fgw {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
'@

Write-Host $StepLabel -ForegroundColor Cyan
Write-Host " — bring Unity to the front; I will detect focus automatically." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($TimeoutSec)
function Test-UnityFocused {
  $h = [Fgw]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return $false }
  [uint32]$fgPid = 0; [void][Fgw]::GetWindowThreadProcessId($h, [ref]$fgPid)
  if ($pid -eq 0) { return $false }
  try {
    $p = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.ProcessName -match '^Unity$') { return $true }
    # Fallback: title contains "Unity"
    if ($p.MainWindowTitle -match 'Unity') { return $true }
    return $false
  } catch { return $false }
}

while (-not (Test-UnityFocused)) {
  if ((Get-Date) -gt $deadline) { throw "Timeout waiting for Unity to get focus." }
  Start-Sleep -Milliseconds 250
}
Write-Host "[unity-focus] Unity focused — waiting for compile completion..." -ForegroundColor Cyan
& $waiter -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec