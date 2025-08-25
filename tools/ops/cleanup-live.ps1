param(
  [string]$RepoRoot = "C:\Users\ander\My project",
  [string]$LiveDir  = (Join-Path $RepoRoot "ops\live"),
  [int]$RetentionDays = 7
)
$ErrorActionPreference = "Stop"

function Step($m){ Write-Host "[cleanup] $m" -ForegroundColor DarkCyan }

if(!(Test-Path $LiveDir)){ Step "live dir missing: $LiveDir"; exit 0 }

$cutUtc = [datetime]::UtcNow.AddDays(-$RetentionDays)

# Only ack files; do NOT touch latest-pointer.md/json, transcripts, errors, etc.
$ackFiles = Get-ChildItem -Path $LiveDir -Filter 'compile-ack_*.txt' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -lt $cutUtc }

if(-not $ackFiles){ Step "nothing to clean (0 files older than $RetentionDays days)"; exit 0 }

$backupDir = Join-Path $LiveDir 'backup'
if(!(Test-Path $backupDir)){ New-Item -ItemType Directory -Path $backupDir | Out-Null }
$zipPath = Join-Path $backupDir ("ack_backup_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".zip")

# Backup
$paths = $ackFiles | ForEach-Object { $_.FullName }
Compress-Archive -Path $paths -DestinationPath $zipPath -Force
if(!(Test-Path $zipPath) -or ((Get-Item $zipPath).Length -le 0)){
  throw "backup zip missing/empty: $zipPath"
}
Step ("backed up " + $ackFiles.Count + " file(s) → " + $zipPath)

# Prune
foreach($f in $ackFiles){ Remove-Item $f.FullName -Force -ErrorAction Stop }
Step ("pruned " + $ackFiles.Count + " old ack file(s)")