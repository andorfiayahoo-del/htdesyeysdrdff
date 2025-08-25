# tools/ops/safepush-run.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [Parameter(Mandatory=$true)][string]$Cmd
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Warning $m }
function Die($m){ Write-Error $m; exit 1 }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
if(!(Test-Path $RepoRoot)){ Die "Repo root not found: $RepoRoot" }
if(!(Test-Path (Join-Path $RepoRoot '.git'))){ Die "Not a git repo: $RepoRoot" }
$LiveDir = Join-Path $RepoRoot 'ops\live'
if(!(Test-Path $LiveDir)){ New-Item -ItemType Directory -Path $LiveDir | Out-Null }
$rid = (Get-Date).ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([guid]::NewGuid().ToString("N"))
$tx = Join-Path $LiveDir ("transcript_" + $rid + ".log")
$errFile = Join-Path $LiveDir ("error_" + $rid + ".txt")
Step "Transcript → $tx"
Start-Transcript -Path $tx | Out-Null
$status = "OK"
try {
  Step "RUN_BEGIN (RID=$rid)"
  Step "EXEC: $Cmd"
  $null = Invoke-Expression $Cmd
} catch {
  $status = "ERROR"
  $msg = ($_ | Out-String).Trim()
  Write-LF $errFile @($msg)
  Write-Error $msg
} finally {
  Stop-Transcript | Out-Null
  if($status -ne "OK"){
    Step "Publishing latest-error.md"
    $pub = Join-Path (Join-Path $RepoRoot 'tools\ops') 'publish-latest-error.ps1'
    if(Test-Path $pub){ & pwsh -NoProfile -ExecutionPolicy Bypass -File $pub -RepoRoot "$RepoRoot" | Out-Null }
    Step "Committing error artifacts"
    git -C "$RepoRoot" add -- "ops/live/latest-error.md" "ops/live/transcript_*" "ops/live/error_*" | Out-Null
    $summary = "ops: ERROR RID=$rid (safepush)"
    git -C "$RepoRoot" commit -m $summary | Out-Null
    $hasVpush = (git -C "$RepoRoot" config --get alias.vpush) -ne $null
    if($hasVpush){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }
  }
  Step "RUN_END status=$status RID=$rid"
  if($status -ne "OK"){ exit 2 }
}