param(
  [string]$ProjectRoot = "$PSScriptRoot\..",
  [string]$OutDir = "$env:USERPROFILE\Desktop\SharedLogs"
)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$zip = Join-Path $OutDir "logs-$stamp.zip"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$paths = @(
  (Join-Path $ProjectRoot "GatewayCJS\*.log"),
  (Join-Path $ProjectRoot "GatewayCJS\pm2-*.txt"),
  (Join-Path $ProjectRoot "Unity\Editor.log"),
  (Join-Path $ProjectRoot "Unity\Player.log")
)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipStream = [System.IO.File]::Open($zip, [System.IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

foreach ($pattern in $paths) {
  Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | ForEach-Object {
    $entry = $_.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
    $archive.CreateEntryFromFile($_.FullName, $entry) | Out-Null
  }
}

$archive.Dispose()
$zipStream.Dispose()
Write-Host "Wrote $zip"
