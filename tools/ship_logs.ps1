param(
  [string]$OutDir
)

if (-not $OutDir -or $OutDir -eq '') {
  if ($env:LOG_SHIP_DEST -and $env:LOG_SHIP_DEST -ne '') {
    $OutDir = $env:LOG_SHIP_DEST
  } else {
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'LogsOutbox'
  }
}

$ErrorActionPreference = 'Continue'

function New-SafePath([string]$p) {
  $safe = $p -replace '[:\\\/]', '_'
  return $safe
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$projectRoot = Split-Path -Parent $PSScriptRoot
$staging = Join-Path $env:TEMP ("unity_logs_" + $timestamp)
$null = New-Item -ItemType Directory -Force -Path $staging | Out-Null
$null = New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$paths = @(
  "$env:LOCALAPPDATA\Unity\Editor\Editor.log",
  "$env:LOCALAPPDATA\Unity\Editor\Editor-prev.log",
  "$env:USERPROFILE\AppData\LocalLow\*\*\Player.log",
  "$env:USERPROFILE\AppData\LocalLow\*\*\output_log.txt",
  "$env:LOCALAPPDATA\Temp\Unity\Editor\Crashes\**\*.*",
  "$env:LOCALAPPDATA\Temp\Unity\Editor\**\Editor.log",
  "$env:USERPROFILE\.pm2\logs\*.log",
  (Join-Path $projectRoot "ProjectSettings\ProjectVersion.txt"),
  (Join-Path $projectRoot "GatewayCJS\*.log"),
  (Join-Path $projectRoot "Logs\**\*.*")
)

$collected = @()

foreach ($pat in $paths) {
  try {
    $matches = Get-ChildItem -Path $pat -File -Recurse -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
      try {
        $safe = New-SafePath($m.FullName.TrimStart('\'))
        $dest = Join-Path $staging $safe
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item -Path $m.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
        $collected += $m.FullName
      } catch { }
    }
  } catch { }
}

$manifest = @{
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  out_dir = $OutDir
  project_root = $projectRoot
  env = @{
    USERPROFILE = $env:USERPROFILE
    LOCALAPPDATA = $env:LOCALAPPDATA
    COMPUTERNAME = $env:COMPUTERNAME
    USERDOMAIN = $env:USERDOMAIN
  }
  collected = $collected
} | ConvertTo-Json -Depth 6

$manifestPath = Join-Path $staging "manifest.json"
$manifest | Out-File -FilePath $manifestPath -Encoding UTF8

$zipPath = Join-Path $OutDir ("logs-" + $timestamp + ".zip")
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force
Write-Host "Log ship complete: $zipPath"
