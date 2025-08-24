param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch='main',
  [string]$RemoteName='origin',
  [string]$Reason='manual'
)
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $RepoRoot
$exit = 1

function New-RunId {
  (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([Guid]::NewGuid().ToString("N"))
}

try {
  # Ensure union-merge for the log
  $attrPath = Join-Path $RepoRoot '.gitattributes'
  $attrLine = 'ops/live/push-flush.log merge=union -diff'
  if (-not (Test-Path -LiteralPath $attrPath)) {
    Set-Content -LiteralPath $attrPath -Value $attrLine -Encoding utf8
  } else {
    $present = Select-String -LiteralPath $attrPath -SimpleMatch 'ops/live/push-flush.log' -Quiet -ErrorAction SilentlyContinue
    if (-not $present) { Add-Content -LiteralPath $attrPath -Value $attrLine -Encoding utf8 }
  }

  $RID = New-RunId
  $env:PUSH_RUN_ID = $RID
  $logRel = 'ops/live/push-flush.log'
  $logAbs = Join-Path $RepoRoot $logRel
  $ts = [DateTime]::UtcNow.ToString('o')
  $preHead = (& git rev-parse HEAD 2>$null).Trim()
  $hostname = $env:COMPUTERNAME; $user = $env:USERNAME
  Add-Content -LiteralPath $logAbs -Value ("[{0}] RID={1} RUN_BEGIN reason={2} preHEAD={3} host={4} user={5}" -f $ts,$RID,$Reason,$preHead,$hostname,$user) -Encoding UTF8

  # Real push + verify (git-sync.ps1 internally calls verify-remote.ps1 which will reuse RID via env)
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'git-sync.ps1') `
      -RepoRoot $RepoRoot -LiveDir $LiveDir -Reason $Reason -Owner $Owner -Repo $Repo -Branch $Branch
  $exit = $LASTEXITCODE
}
finally {
  try {
    $status = if ($exit -eq 0) { 'OK' } else { 'FAIL' }
    $ts2 = [DateTime]::UtcNow.ToString('o')
    $postHead = (& git rev-parse HEAD 2>$null).Trim()
    $LogRID = New-RunId  # unique id for this specific log write/commit
    Add-Content -LiteralPath $logAbs -Value ("[{0}] RID={1} RUN_END status={2} postHEAD={3} LOGRID={4}" -f $ts2,$RID,$status,$postHead,$LogRID) -Encoding UTF8

    & git add -- \ '.gitattributes' | Out-Null
    & git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
      $short = (& git rev-parse --short HEAD 2>$null).Trim()
      & git commit -m ("ops: update push-flush.log rid={0} logrid={1} [{2}]" -f $RID,$LogRID,$short) --no-gpg-sign | Out-Null
      for ($try=1; $try -le 4; $try++) {
        & git push $RemoteName $Branch
        if ($LASTEXITCODE -eq 0) { break }
        & git -c pull.rebase=true pull --rebase $RemoteName $Branch
        if ($LASTEXITCODE -ne 0) {
          & git add -- \ '.gitattributes' | Out-Null
          & git rebase --continue 2>$null | Out-Null
        }
      }
    }
  } catch { }
  Pop-Location
}
exit $exit

