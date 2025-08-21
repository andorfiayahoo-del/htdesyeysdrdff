param(
  [string]$RepoRoot  = "C:\Users\ander\My project",
  [string]$RouterSrcRel = "tools\inbox-router\inbox-router.ps1",
  [string]$UserRouter = "C:\Users\ander\inbox-router.ps1",
  [string]$LogPath    = "$env:USERPROFILE\patch-router.log"
)

$ErrorActionPreference = "Stop"

$RouterSrc = Join-Path $RepoRoot $RouterSrcRel
$RouterBak = $RouterSrc + ".bak"
$psExe     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Stop-Router { param([string]$dst)
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match [regex]::Escape($dst) } |
    ForEach-Object { try { Stop-Process -Id $_.Id -Force } catch {} }
}

Set-Location -LiteralPath $RepoRoot

# Sizes (PS 5.1-safe)
$sizeNow = -1; if (Test-Path -LiteralPath $RouterSrc) { $sizeNow = (Get-Item -LiteralPath $RouterSrc).Length }
$sizeBak = -1; if (Test-Path -LiteralPath $RouterBak) { $sizeBak = (Get-Item -LiteralPath $RouterBak).Length }
Write-Host ("Router.ps1 size now: {0}   .bak size: {1}" -f $sizeNow,$sizeBak) -ForegroundColor Cyan

# Prefer .bak (>10KB), else HEAD~1
$restored = $false
if ((Test-Path -LiteralPath $RouterBak) -and ($sizeBak -gt 10000)) {
  Copy-Item -LiteralPath $RouterBak -Destination $RouterSrc -Force
  Write-Host "[RESTORE] Copied .bak over router.ps1" -ForegroundColor Yellow
  $restored = $true
} else {
  $null = & git rev-parse HEAD~1 2>$null
  if ($LASTEXITCODE -eq 0) {
    $tmp = Join-Path $env:TEMP ("router-prev-{0}.ps1" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $content = & git show "HEAD~1:$RouterSrcRel" 2>$null
    if ($LASTEXITCODE -eq 0 -and $content) {
      $content | Set-Content -LiteralPath $tmp -Encoding UTF8
      if ((Get-Item -LiteralPath $tmp).Length -gt 10000) {
        Copy-Item -LiteralPath $tmp -Destination $RouterSrc -Force
        Write-Host "[RESTORE] Recovered router from HEAD~1" -ForegroundColor Yellow
        $restored = $true
      }
    }
  }
}
if (-not $restored) { Write-Host "[WARN] No restore source found; keeping current file." -ForegroundColor Yellow }

# Keep origin in sync (non-fatal if nothing to commit)
& git add -A
& git commit -m "recovery: add PS5.1-safe Restore-Router-PS51 helper and sync router state" 2>$null
& git -c rebase.autoStash=true pull --rebase origin main
& git push -u origin HEAD:main

# Sync to user path & restart
Copy-Item -LiteralPath $RouterSrc -Destination $UserRouter -Force
try { Unblock-File -LiteralPath $UserRouter } catch {}
Stop-Router $UserRouter
Remove-Item -LiteralPath $LogPath -ErrorAction SilentlyContinue
Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$UserRouter) -WindowStyle Normal

# Confirm the usual BOOT/SCRIPT/WATCH lines
for ($i=0; $i -lt 40 -and -not (Test-Path -LiteralPath $LogPath); $i++){ Start-Sleep -Milliseconds 250 }
if (Test-Path -LiteralPath $LogPath) {
  Get-Content -LiteralPath $LogPath -Tail 3
} else {
  Write-Host "[WARN] No log yet." -ForegroundColor Yellow
}
