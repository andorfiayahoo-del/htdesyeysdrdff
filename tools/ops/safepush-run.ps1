# tools/ops/safepush-run.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [Parameter(Mandatory=$true)][string]$Cmd
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Warning $m }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
if(!(Test-Path $RepoRoot)){ throw "Repo root not found: $RepoRoot" }
if(!(Test-Path (Join-Path $RepoRoot '.git'))){ throw "Not a git repo: $RepoRoot" }
$LiveDir = Join-Path $RepoRoot 'ops\live' ; if(!(Test-Path $LiveDir)){ New-Item -ItemType Directory -Path $LiveDir | Out-Null }
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
  try { Stop-Transcript | Out-Null } catch { }
  if($status -ne "OK"){
    Step "Publishing latest-error.md (non-fatal)"
    $pub = Join-Path (Join-Path $RepoRoot 'tools\ops') 'publish-latest-error.ps1'
    $pubOK = $false
    if(Test-Path $pub){
      try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $pub -RepoRoot "$RepoRoot" 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) { $pubOK = $true } else { Warn "publisher exitcode=$LASTEXITCODE" }
      } catch { Warn ("publisher error: " + $_.Exception.Message) }
    }
    # Fallback: synthesize minimal latest-error.md if publisher didn't produce one
    $latestMD = Join-Path $LiveDir 'latest-error.md'
    if(-not (Test-Path $latestMD)){
      $tail = @() ; try { $tail = Get-Content $tx -Tail 80 } catch { }
      $errTxt = @() ; try { if(Test-Path $errFile){ $errTxt = Get-Content $errFile } } catch { }
      $md = @("# Latest Error Snapshot","","**RID:** $rid  ","**Status:** ERROR  ", ("**Error:** " + (($errTxt -join " ") ?? "(none)")), "", "```text") + $tail + @("```")
      Write-LF $latestMD $md
    }
    Step "Committing error artifacts"
    try {
      git -C "$RepoRoot" add -- "ops/live/latest-error.md" "ops/live/transcript_*" "ops/live/error_*" | Out-Null
      $changes = (git -C "$RepoRoot" status --porcelain) -ne ""
      if($changes){
        git -C "$RepoRoot" commit -m ("ops: ERROR RID=" + $rid + " (safepush)") | Out-Null
        $hasVpush = (git -C "$RepoRoot" config --get alias.vpush) -ne $null
        if($hasVpush){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }
      } else { Warn "nothing to commit (already captured?)" }
    } catch { Warn ("commit/push failure: " + $_.Exception.Message) }
  }
  Step "RUN_END status=$status RID=$rid"
  if($status -ne "OK"){ exit 2 }
}