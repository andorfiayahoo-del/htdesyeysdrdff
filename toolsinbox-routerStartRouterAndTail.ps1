# Starts the router and a color tailer; kills any legacy tailers first
param(
  [string]$RepoRoot = 'C:\Users\ander\My project'
)

$RouterSrc = Join-Path $RepoRoot 'tools\inbox-router\inbox-router.ps1'
$RouterDst = 'C:\Users\ander\inbox-router.ps1'
$TailerSrc = Join-Path $RepoRoot 'tools\router-tail.ps1'
$LogPath   = "$env:USERPROFILE\patch-router.log"
$psExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Write-Host "== StartRouterAndTail: using tailer $TailerSrc" -ForegroundColor Cyan

# Kill any legacy tailers (any powershell running *router-tail.ps1*)
$legacy = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -match 'powershell' -and $_.CommandLine -match 'router-tail\.ps1'
}
foreach ($p in $legacy) {
  try { Stop-Process -Id $p.ProcessId -Force; Write-Host "Killed legacy tailer PID $($p.ProcessId)" -ForegroundColor DarkYellow } catch {}
}

# Copy latest router to user path
Copy-Item -LiteralPath $RouterSrc -Destination $RouterDst -Force
try { Unblock-File -LiteralPath $RouterDst } catch {}

# Stop previous router, clear old log, start new router window
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match [regex]::Escape($RouterDst) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Remove-Item -LiteralPath $LogPath -ErrorAction SilentlyContinue
Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$RouterDst) -WindowStyle Normal

# Launch color tailer in a new window
if (-not (Test-Path -LiteralPath $TailerSrc)) {
  Write-Host "Tailer not found at $TailerSrc (apply tailer patch)." -ForegroundColor Yellow
} else {
  Write-Host "Launching color tailer window..." -ForegroundColor Cyan
  Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$TailerSrc,'-LogPath',$LogPath) -WindowStyle Normal
}

