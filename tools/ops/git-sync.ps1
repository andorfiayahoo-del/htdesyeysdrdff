param([string]$RepoRoot,[string]$LiveDir,[string]$RemoteName="origin",[string]$BranchName="main",[string]$Reason="event",[string]$Owner="andorfiayahoo-del",[string]$Repo="htdesyeysdrdff")
$ErrorActionPreference="Stop"
$FlushLog=Join-Path $LiveDir "push-flush.log"
function LogF([string]$m){ try{ $ts=[DateTime]::UtcNow.ToString("o"); Add-Content -LiteralPath $FlushLog -Value "[$ts] $m" -Encoding UTF8 }catch{} }

if(-not (Test-Path -LiteralPath $RepoRoot)){ LogF "GIT_SYNC_FAIL: RepoRoot missing"; exit 2 }
New-Item -ItemType Directory -Force -Path $LiveDir | Out-Null
Push-Location -LiteralPath $RepoRoot
try{
  & git rev-parse --is-inside-work-tree *> $null
  if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: not a work tree"; exit 2 }

  # Capture remote SHA before pushing (for changed-file range)
  $oldLine = & git ls-remote $RemoteName ("refs/heads/$BranchName")
  $oldSha  = if($LASTEXITCODE -eq 0 -and $oldLine){ ($oldLine -split '\s+')[0] } else { '' }

  & git add -A *> $null
  & git diff --cached --quiet *> $null; $hasStaged = ($LASTEXITCODE -ne 0)
  if($hasStaged){
    $stamp=[DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    & git commit -m "sync: auto ($Reason) $stamp" --no-gpg-sign *> $null
    if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: commit failed"; exit 2 }
    LogF "GIT_SYNC_COMMIT_OK"
  } else { LogF "GIT_SYNC_NOOP (nothing to commit)" }

  & git push $RemoteName $BranchName *> $null
  if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: push failed"; exit 2 }
  LogF "GIT_SYNC_PUSH_OK"

  # Strict remote verification: wait for RAW/Blob to match exact blob bytes
  $verifier = Join-Path $PSScriptRoot 'verify-remote.ps1'
  if(Test-Path -LiteralPath $verifier){
    pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier `
      -RepoRoot $RepoRoot -LiveDir $LiveDir -Owner $Owner -Repo $Repo `
      -Branch $BranchName -RemoteName $RemoteName -OldRemoteSha $oldSha
    $vc = $LASTEXITCODE
    if($vc -eq 0){
      LogF "GIT_VERIFY_OK (strict)"
    } else {
      LogF ("GIT_VERIFY_FAIL ec={0} (see VERIFY_* lines above)" -f $vc)
      exit $vc
    }
  } else {
    LogF "GIT_SYNC_NOTE: verifier not found; skipping strict check"
  }
  exit 0
} finally { Pop-Location }