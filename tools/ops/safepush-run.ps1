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
    $pub      = Join-Path (Join-Path $RepoRoot 'tools\ops') 'publish-latest-error.ps1'
    $latestMD = Join-Path $LiveDir 'latest-error.md'
    $pointer  = Join-Path $LiveDir 'latest-pointer.json'
    $pubOK = $false
    if(Test-Path $pub){
      $oldNative = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
      try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $pub -RepoRoot "$RepoRoot" -Rid $rid | Out-Null
        $ec = $LASTEXITCODE
        if ($ec -eq 0) { $pubOK = $true } else { Warn ("publisher exitcode=" + $ec) }
      } catch {
        Warn ("publisher exception: " + $_.Exception.Message)
      } finally {
        $PSNativeCommandUseErrorActionPreference = $oldNative
      }
    }
    # Fallbacks if publisher didn't create artifacts
    if(-not (Test-Path $latestMD)){
      $tail = @(); try { $tail = Get-Content $tx -Tail 80 } catch { }
      $errTxt = @(); try { if(Test-Path $errFile){ $errTxt = Get-Content $errFile } } catch { }
      $errJoined = if ($errTxt -and $errTxt.Count -gt 0) { ($errTxt -join ' ') } else { '(none)' }
      $md = @('# Latest Error Snapshot','','**RID:** ' + $rid + '  ','**Status:** ERROR  ','**Error:** ' + $errJoined + '  ','','```text') + $tail + @('```')
      Write-LF $latestMD $md
    }
    if(-not (Test-Path $pointer)){
      $head = '' ; try { $head = (git -C "$RepoRoot" rev-parse HEAD).Trim() } catch { }
      $efile = '' ; $eline = '' ;
      try {
        $rawErr = if(Test-Path $errFile){ Get-Content $errFile -Raw } else { "" }
        $mm = [regex]::Match($rawErr, 'ParserError:\s+(.+?):(\d+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if($mm.Success){ $efile = $mm.Groups[1].Value; $eline = $mm.Groups[2].Value }
      } catch { }
      $txPath = $tx
      $errTxtPath = if(Test-Path $errFile){ $errFile } else { "" }
      $ptr = [pscustomobject]@{ rid = $rid; status = "ERROR"; head = $head; file = $efile; line = $eline; files = [pscustomobject]@{ error_md = $latestMD; transcript = $txPath; error_txt = $errTxtPath } }
      $json = ($ptr | ConvertTo-Json -Depth 6)
      Write-LF $pointer @($json)
    }
    Step "Committing error artifacts"
    try {
      $toAdd = New-Object System.Collections.Generic.List[string]
      if(Test-Path $latestMD){ $toAdd.Add($latestMD) }
      if(Test-Path $pointer){  $toAdd.Add($pointer) }
      $tfs = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue
      $efs = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt' -ErrorAction SilentlyContinue
      foreach($f in @($tfs + $efs)){ $toAdd.Add($f.FullName) }
      foreach($p in $toAdd){ git -C "$RepoRoot" add -- $p | Out-Null }
      $changes = git -C "$RepoRoot" status --porcelain
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