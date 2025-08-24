param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Reason = "manual",
  [string]$Owner,
  [string]$Repo,
  [string]$Branch = "main",
  [string]$RemoteName = "origin"
)
$ErrorActionPreference = "Stop"

function New-RunId {
  (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([Guid]::NewGuid().ToString("N"))
}
# Respect incoming RID from wrapper; generate if missing
$RID = if ($env:PUSH_RUN_ID) { $env:PUSH_RUN_ID } else { New-RunId }

function LogF([string]$m){
  try{
    $ts=[DateTime]::UtcNow.ToString("o")
    $line = "[{0}] RID={1} {2}" -f $ts,$RID,$m
    Add-Content -LiteralPath (Join-Path $LiveDir "push-flush.log") -Value $line -Encoding UTF8
  }catch{}
}

Push-Location -LiteralPath $RepoRoot
try{
  # Remember HEAD before any commit/push (used as OldRemoteSha hint)
  $preHead = (& git rev-parse HEAD 2>$null).Trim()

  # Stage everything EXCEPT the log (wrapper commits the log)
  & git add -A
  & git restore --staged -- "ops/live/push-flush.log" 2>$null | Out-Null

  & git diff --cached --quiet
  if ($LASTEXITCODE -ne 0) {
    $msg = ("sync: auto ({0}) {1}" -f $Reason, (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
    & git commit -m $msg --no-gpg-sign
    if ($LASTEXITCODE -eq 0) { LogF "GIT_SYNC_COMMIT_OK" } else { LogF ("GIT_SYNC_COMMIT_FAIL ec={0}" -f $LASTEXITCODE) }
  } else {
    LogF "GIT_SYNC_COMMIT_SKIP (nothing staged)"
  }

  # Push with light retry
  $pushOk = $false
  for($i=1; $i -le 3; $i++){
    & git push $RemoteName $Branch
    if ($LASTEXITCODE -eq 0) { $pushOk = $true; LogF "GIT_SYNC_PUSH_OK"; break }
    LogF ("GIT_SYNC_PUSH_RETRY attempt={0} ec={1}" -f $i,$LASTEXITCODE)
    & git -c pull.rebase=true pull --rebase $RemoteName $Branch
    if ($LASTEXITCODE -ne 0) {
      & git rebase --continue 2>$null | Out-Null
    }
  }

  # Run strict verify and CAPTURE ITS OUTPUT into this log (in addition to its own logging)
  $verifyPath = Join-Path $PSScriptRoot 'verify-remote.ps1'
  $exists = Test-Path -LiteralPath $verifyPath
  $len = if ($exists) { (Get-Item -LiteralPath $verifyPath).Length } else { 0 }
  LogF ("GIT_VERIFY_PATH_EXISTS={0} len={1} path={2}" -f $exists, $len, $verifyPath)

  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
  if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source }
  LogF ("GIT_VERIFY_PWSH={0}" -f $pwsh)

  if ($exists -and $pwsh) {
    $argv = @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File', $verifyPath,
      '-RepoRoot', $RepoRoot, '-LiveDir', $LiveDir,
      '-Owner', $Owner, '-Repo', $Repo, '-Branch', $Branch,
      '-RemoteName', $RemoteName, '-OldRemoteSha', $preHead
    )
    LogF ("GIT_VERIFY_ARGV={0}" -f ([string]::Join(' ', ($argv | ForEach-Object { if($_ -match '\s|"'){ '"' + ($_ -replace '"','""') + '"' } else { $_ } })) ))
    LogF "GIT_VERIFY_RUN"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName  = $pwsh
    $psi.Arguments = [string]::Join(' ', ($argv | ForEach-Object { if($_ -match '\s|"'){ '"' + ($_ -replace '"','""') + '"' } else { $_ } }))
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)

    # Read all output; write each line back into our log with RID
    $stdOut = $p.StandardOutput.ReadToEnd()
    $stdErr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($stdOut) {
      foreach($line in ($stdOut -split "`r?`n")) {
        if ($line.Trim().Length -gt 0) { LogF ("VERIFY_STDOUT {0}" -f ($line -replace '\s+$','')) }
      }
    }
    if ($stdErr) {
      foreach($line in ($stdErr -split "`r?`n")) {
        if ($line.Trim().Length -gt 0) { LogF ("VERIFY_STDERR {0}" -f ($line -replace '\s+$','')) }
      }
    }

    $ec = $p.ExitCode
    LogF ("GIT_VERIFY_EXIT={0}" -f $ec)
    if ($ec -ne 0) { LogF ("GIT_VERIFY_FAIL ec={0}" -f $ec); exit 64 } else { LogF "GIT_VERIFY_OK"; exit 0 }
  }
  else {
    LogF "GIT_VERIFY_SKIP (missing pwsh or verify script)"
    exit 0
  }
}
catch{
  $t = $_.Exception.GetType().FullName
  LogF ("GIT_SYNC_EX type={0} msg={1}" -f $t, $_.Exception.Message)
  if ($_.InvocationInfo) { LogF ("GIT_SYNC_EX_AT {0}" -f $_.InvocationInfo.PositionMessage.Replace("`r"," ").Replace("`n"," ")) }
  exit 1
}
finally { Pop-Location }
