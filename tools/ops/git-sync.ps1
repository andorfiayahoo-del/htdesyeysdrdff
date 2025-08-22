param([string]$RepoRoot,[string]$LiveDir,[string]$RemoteName="origin",[string]$BranchName="main",[string]$Reason="event")
$ErrorActionPreference="Stop"
$FlushLog=Join-Path $LiveDir "push-flush.log"
function LogF([string]$m){ try{ $ts=[DateTime]::UtcNow.ToString("o"); Add-Content -LiteralPath $FlushLog -Value "[$ts] $m" -Encoding UTF8 }catch{} }

if(-not (Test-Path -LiteralPath $RepoRoot)){ LogF "GIT_SYNC_FAIL: RepoRoot missing"; exit 2 }
Push-Location -LiteralPath $RepoRoot
try{
  & git rev-parse --is-inside-work-tree *> $null
  if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: not a work tree"; exit 2 }

  & git add -A *> $null
  & git diff --cached --quiet *> $null
  $hasStaged = ($LASTEXITCODE -ne 0)
  if($hasStaged){
    $stamp=[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    & git commit -m "sync: auto ($Reason) $stamp" --no-gpg-sign *> $null
    if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: commit failed"; exit 2 }
    LogF "GIT_SYNC_COMMIT_OK"
  } else {
    LogF "GIT_SYNC_NOOP (nothing to commit)"
  }

  # Push
  & git push $RemoteName $BranchName *> $null
  if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: push failed"; exit 2 }
  LogF "GIT_SYNC_PUSH_OK"

  # Verify remote matches local HEAD (retry a few times for backend propagation)
  $local = (& git rev-parse HEAD).Trim()
  $ok = $false
  for($i=0;$i -lt 10 -and -not $ok;$i++){
    $ls = (& git ls-remote $RemoteName HEAD 2>$null)
    if($LASTEXITCODE -eq 0 -and $ls){
      $remote = ($ls -split "`t| ")[0].Trim()
      if($remote -eq $local){ $ok=$true; break }
    }
    Start-Sleep -Milliseconds 600
  }
  if($ok){
    LogF "GIT_REMOTE_OK sha=$local"
    exit 0
  } else {
    LogF "GIT_REMOTE_MISMATCH local=$local"
    exit 3
  }
}
finally { Pop-Location }