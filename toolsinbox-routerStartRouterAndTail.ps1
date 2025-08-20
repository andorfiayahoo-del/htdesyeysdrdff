# Starts the router and a color tailer side-by-side
param(
  [string]$RepoRoot = 'C:\Users\ander\My project'
)

$RouterSrc = Join-Path $RepoRoot 'tools\inbox-router\inbox-router.ps1'
$RouterDst = 'C:\Users\ander\inbox-router.ps1'
$TailerSrc = Join-Path $RepoRoot 'tools\router-tail.ps1'
$LogPath   = "$env:USERPROFILE\patch-router.log"
$psExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Copy latest router to user path
Copy-Item -LiteralPath $RouterSrc -Destination $RouterDst -Force
try { Unblock-File -LiteralPath $RouterDst } catch {}

# Stop previous router, clear old log, start new router window
Get-CimInstance Win32_Process | ? { $_.CommandLine -match [regex]::Escape($RouterDst) } | % { try { Stop-Process -Id $_.Id -Force } catch {} }
Remove-Item -LiteralPath $LogPath -ErrorAction SilentlyContinue
Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$RouterDst) -WindowStyle Normal

# Start color tailer in this window
if (-not (Test-Path -LiteralPath $TailerSrc)) {
  Write-Host "Tailer not found at $TailerSrc (apply tailer patch)." -ForegroundColor Yellow
} else {
  Write-Host "Launching color tailer..." -ForegroundColor Cyan
  & powershell -NoProfile -ExecutionPolicy Bypass -File $TailerSrc -LogPath $LogPath
}

