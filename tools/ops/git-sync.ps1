param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$RemoteName="origin",
  [string]$BranchName="main",
  [string]$Reason="event",
  [string]$Owner="andorfiayahoo-del",
  [string]$Repo="htdesyeysdrdff"
)
$ErrorActionPreference="Stop"
$FlushLog = Join-Path $LiveDir "push-flush.log"
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
  } else {
    LogF "GIT_SYNC_NOOP (nothing to commit)"
  }

  & git push $RemoteName $BranchName *> $null
  if($LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: push failed"; exit 2 }
  LogF "GIT_SYNC_PUSH_OK"

  # ---- STRICT VERIFIER LAUNCH (deep logs) ----
  $verifier = Join-Path $PSScriptRoot 'verify-remote.ps1'
  $exists   = Test-Path -LiteralPath $verifier
  $len      = $exists ? ([int](Get-Item -LiteralPath $verifier).Length) : -1
  LogF ("GIT_VERIFY_PATH_EXISTS={0} len={1} path={2}" -f $exists,$len,$verifier)

  if($exists){
    try{
      $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
      LogF ("GIT_VERIFY_PWSH={0}" -f $pwsh)

      $argv = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', $verifier,
        '-RepoRoot', $RepoRoot, '-LiveDir', $LiveDir, '-Owner', $Owner, '-Repo', $Repo,
        '-Branch', $BranchName, '-RemoteName', $RemoteName, '-OldRemoteSha', $oldSha
      )

      # Log the exact argv we pass (joined with spaces, quoting paths)
      $argvLog = ($argv | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"','""') + '"' } else { $_ }
      }) -join ' '
      LogF ("GIT_VERIFY_ARGV={0}" -f $argvLog)

      LogF "GIT_VERIFY_RUN"
      $proc = Start-Process -FilePath $pwsh -ArgumentList $argv -PassThru -WindowStyle Hidden -Wait
      $vc   = $proc.ExitCode
      LogF ("GIT_VERIFY_EXIT={0}" -f $vc)
    } catch {
      LogF ("GIT_VERIFY_EX launcher msg={0}" -f $_.Exception.Message)
      $vc = 1
    }

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