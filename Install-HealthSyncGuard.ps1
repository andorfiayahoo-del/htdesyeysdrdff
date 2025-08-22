#requires -Version 7.0
<# 
Install-Health+Sync-Guard.ps1
Event-driven Git health + sync guard (no timers), versioned hooks, and docs.
#>

$ErrorActionPreference = 'Stop'

# --- SETTINGS (adjust if your paths differ) ---
$RepoRoot    = 'C:\Users\ander\My project'
$OpsDir      = Join-Path $RepoRoot 'tools\ops'
$HooksDir    = Join-Path $RepoRoot 'tools\git-hooks'
$LiveDir     = Join-Path $RepoRoot 'ops\live'

$PusherPath  = Join-Path $OpsDir   'push-on-apply.ps1'   # your existing pusher
$WrapPath    = Join-Path $OpsDir   'push-flush-wrap.ps1' # wrapper we (re)write
$HealthPath  = Join-Path $OpsDir   'git-health.ps1'
$SyncPath    = Join-Path $OpsDir   'git-sync.ps1'

$PrePushCmd  = Join-Path $HooksDir 'pre-push.cmd'
$PostCommitCmd = Join-Path $HooksDir 'post-commit.cmd'

$ReadmePath  = Join-Path $RepoRoot 'README.md'
$HandoverMd  = Join-Path $RepoRoot 'handover\Handover-Instructions.md'

$RemoteName  = 'origin'
$BranchName  = 'main'

# --- Helpers ---
function OK   ($m){ Write-Host "[OK]  $m" -ForegroundColor Green }
function WARN ($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function ERR  ($m){ Write-Host "[ERR] $m" -ForegroundColor Red }

function GitRun {
  param([string[]]$Args)
  $Args = @($Args | Where-Object { $_ -ne $null -and $_ -ne '' })
  if($Args.Count -eq 0){ return @{ out=''; err=''; code=0 } }
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'git'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.CreateNoWindow = $true
  $psi.Arguments = [string]::Join(' ', ($Args | ForEach-Object {
    if($_ -match '[\s"]'){ '"' + ($_ -replace '"','""') + '"' } else { $_ }
  }))
  $p   = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit() | Out-Null
  return @{ out=$out; err=$err; code=$p.ExitCode }
}

function Write-Utf8NoBom { param([string]$Path,[string]$Content)
  $dir=[System.IO.Path]::GetDirectoryName($Path)
  if($dir -and -not (Test-Path -LiteralPath $dir)){ [void][System.IO.Directory]::CreateDirectory($dir) }
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Content,$utf8)
}

function Patch-DocSection {
  param([string]$Path,[string]$Marker,[string]$Body)
  $begin="<!-- $Marker:BEGIN -->"
  $end  ="<!-- $Marker:END -->"
  $block="$begin`r`n$Body`r`n$end`r`n"
  $txt = (Test-Path -LiteralPath $Path) ? (Get-Content -LiteralPath $Path -Raw) : "# $(Split-Path $Path -Leaf)`r`n"
  if($txt -match [regex]::Escape($begin) -and $txt -match [regex]::Escape($end)){
    $pat="(?s)"+[regex]::Escape($begin)+".*?"+[regex]::Escape($end)
    $txt=[regex]::Replace($txt,$pat,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
  } else {
    if(-not $txt.EndsWith("`r`n")){ $txt+="`r`n" }
    $txt+="`r`n$block"
  }
  Write-Utf8NoBom -Path $Path -Content $txt
}

# --- Ensure base folders ---
if(-not (Test-Path -LiteralPath $RepoRoot)){ throw "RepoRoot not found: $RepoRoot" }
[void][System.IO.Directory]::CreateDirectory($OpsDir)
[void][System.IO.Directory]::CreateDirectory($HooksDir)
[void][System.IO.Directory]::CreateDirectory($LiveDir)

# --- 0) Ensure repo + remotes + main + safe.directory ---
Set-Location -LiteralPath $RepoRoot
[void](GitRun @('config','--global','--add','safe.directory',$RepoRoot))
$inside = GitRun @('rev-parse','--is-inside-work-tree')
if($inside.code -ne 0 -or $inside.out.Trim() -ne 'true'){
  [void](GitRun @('init'))
  [void](GitRun @('checkout','-B',$BranchName))
  OK "Initialized git repo on '$BranchName'."
} else { OK "Git working tree detected." }
$cur = (GitRun @('rev-parse','--abbrev-ref','HEAD')).out.Trim()
if($cur -ne $BranchName){
  [void](GitRun @('checkout','-B',$BranchName))
  OK "Checked out '$BranchName'."
}
$rem = (GitRun @('remote','-v')).out
if($rem -notmatch '^\s*origin\s+'){ WARN "No 'origin' remote found. You may add it later if needed." }

# --- 1) Write git-health.ps1 ---
$HealthPath = Join-Path $OpsDir 'git-health.ps1'
$healthSrc = @"
param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$RemoteName = 'origin',
  [string]$BranchName = 'main'
)
`$ErrorActionPreference = 'Stop'

`$FlushLog = Join-Path `$LiveDir 'push-flush.log'
`$StatusJ  = Join-Path `$LiveDir 'git-health.json'
`$Sentinel = Join-Path `$LiveDir 'GIT-DISCONNECTED.txt'

function LogF([string]`$m){
  try{ `$ts=[DateTime]::UtcNow.ToString('o'); Add-Content -LiteralPath `$FlushLog -Value "[`$ts] `$m" -Encoding UTF8 }catch{}
}
function JsonOut([hashtable]`$obj){
  try{ (`$obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath `$StatusJ -Encoding UTF8 }catch{}
}

`$status = @{
  utc            = [DateTime]::UtcNow.ToString('o')
  repoRoot       = `$RepoRoot
  remoteName     = `$RemoteName
  branchName     = `$BranchName
  ok             = `$true
  checks         = @()
  failureReason  = $null
}
function AddCheck([string]`$name,[bool]`$ok,[string]`$detail){
  `$status.checks += @{ name=`$name; ok=`$ok; detail=`$detail }
  if(-not `$ok){ `$status.ok = `$false }
}

if(-not (Test-Path -LiteralPath `$RepoRoot)){
  AddCheck 'RepoRootExists' `$false "Missing `$RepoRoot"; `$status.failureReason="RepoRoot missing"; goto :Finalize
}else{ AddCheck 'RepoRootExists' `$true 'ok' }

Push-Location -LiteralPath `$RepoRoot
try{
  `$isWT = & git rev-parse --is-inside-work-tree 2>$null
  if(`$LASTEXITCODE -ne 0 -or (`$isWT|Out-String).Trim() -ne 'true'){
    AddCheck 'IsInsideWorkTree' `$false 'Not a git work tree'; `$status.failureReason="Not a git work tree"; goto :FinalizePop
  } else { AddCheck 'IsInsideWorkTree' `$true 'ok' }

  `$remoteUrl = & git remote get-url `$RemoteName 2>$null
  if(`$LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace((`$remoteUrl|Out-String).Trim())){
    AddCheck 'RemotePresent' `$false "Remote '`$RemoteName' not set"; `$status.failureReason="Remote not set"; goto :FinalizePop
  } else { AddCheck 'RemotePresent' `$true ((`$remoteUrl|Out-String).Trim()) }

  & git ls-remote --heads `$RemoteName `$BranchName *> `$null
  if(`$LASTEXITCODE -ne 0){
    AddCheck 'RemoteReachable' `$false "ls-remote failed"; `$status.failureReason="Remote unreachable"; goto :FinalizePop
  } else { AddCheck 'RemoteReachable' `$true 'ok' }

  & git push --dry-run `$RemoteName HEAD:refs/heads/`$BranchName *> `$null
  if(`$LASTEXITCODE -ne 0){
    AddCheck 'DryRunPush' `$false "push --dry-run failed"; `$status.failureReason="Dry-run push failed"; goto :FinalizePop
  } else { AddCheck 'DryRunPush' `$true 'ok' }

} finally { :FinalizePop Pop-Location }

:Finalize
JsonOut `$status
if(`$status.ok){
  LogF "GIT_HEALTH_OK remote=`$RemoteName branch=`$BranchName"
  if(Test-Path -LiteralPath `$Sentinel){ try{ Remove-Item -LiteralPath `$Sentinel -Force }catch{} }
  exit 0
} else {
  LogF "GIT_HEALTH_FAIL reason=`$(`$status.failureReason)"
  try{
    Set-Content -LiteralPath `$Sentinel -Encoding UTF8 -Value @"
Git repo appears **disconnected** (reason: `$(`$status.failureReason)).

What to do:
  1) Open pwsh in `"$RepoRoot"`.
  2) Run your saved **Repair/Reconnect** snippet (or ask assistant).
  3) Re-run the patch cycle; health will go green.

(Written by tools/ops/git-health.ps1 on each apply/push event.)
"@
  }catch{}
  exit 2
}
"@
Write-Utf8NoBom -Path $HealthPath -Content $healthSrc
OK "Wrote tools/ops/git-health.ps1"

# --- 2) Write git-sync.ps1 ---
$SyncPath = Join-Path $OpsDir 'git-sync.ps1'
$syncSrc = @"
param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$RemoteName = 'origin',
  [string]$BranchName = 'main',
  [string]$Reason     = 'event'
)
`$ErrorActionPreference = 'Stop'
`$FlushLog = Join-Path `$LiveDir 'push-flush.log'
function LogF([string]`$m){ try{ `$ts=[DateTime]::UtcNow.ToString('o'); Add-Content -LiteralPath `$FlushLog -Value "[`$ts] `$m" -Encoding UTF8 }catch{} }

if(-not (Test-Path -LiteralPath `$RepoRoot)){ LogF "GIT_SYNC_FAIL: RepoRoot missing"; exit 2 }
Push-Location -LiteralPath `$RepoRoot
try{
  & git rev-parse --is-inside-work-tree *> `$null
  if(`$LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: not a work tree"; exit 2 }

  & git add -A *> `$null

  & git diff --cached --quiet *> `$null
  `$hasStaged = (`$LASTEXITCODE -ne 0)
  if(`$hasStaged){
    `$stamp=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    & git commit -m "sync: auto ($Reason) `$stamp" --no-gpg-sign *> `$null
    if(`$LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: commit failed"; exit 2 }
    LogF "GIT_SYNC_COMMIT_OK"
  } else {
    LogF "GIT_SYNC_NOOP (nothing to commit)"
  }

  & git push `$RemoteName `$BranchName *> `$null
  if(`$LASTEXITCODE -ne 0){ LogF "GIT_SYNC_FAIL: push failed"; exit 2 }
  LogF "GIT_SYNC_PUSH_OK"
  exit 0
} finally { Pop-Location }
"@
Write-Utf8NoBom -Path $SyncPath -Content $syncSrc
OK "Wrote tools/ops/git-sync.ps1"

# --- 3) Versioned hooks ---
$prePushCmdSrc = @"
@echo off
setlocal
set "REPO=%CD%"
set "LIVEDIR=%REPO%\ops\live"
if not exist "%LIVEDIR%" mkdir "%LIVEDIR%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tools\ops\git-health.ps1" -RepoRoot "%REPO%" -LiveDir "%LIVEDIR%" -RemoteName origin -BranchName main
set HC=%ERRORLEVEL%
if not "%HC%"=="0" (
  echo [pre-push] Git health failed (ec=%HC%). Aborting push. 1>&2
  exit /b 1
)
exit /b 0
"@
Write-Utf8NoBom -Path (Join-Path $HooksDir 'pre-push.cmd') -Content $prePushCmdSrc
OK "Wrote tools/git-hooks/pre-push.cmd"

$postCommitCmdSrc = @"
@echo off
setlocal
set "REPO=%CD%"
set "LIVEDIR=%REPO%\ops\live"
if not exist "%LIVEDIR%" mkdir "%LIVEDIR%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tools\ops\git-sync.ps1" -RepoRoot "%REPO%" -LiveDir "%LIVEDIR%" -Reason "post-commit"
exit /b 0
"@
Write-Utf8NoBom -Path (Join-Path $HooksDir 'post-commit.cmd') -Content $postCommitCmdSrc
OK "Wrote tools/git-hooks/post-commit.cmd"

[void](GitRun @('config','core.hooksPath','tools/git-hooks'))
OK "Configured core.hooksPath = tools/git-hooks"

# --- 4) Wrap flusher to run health first ---
$wrapSrc = @"
param(
  [string]$RepoRoot     = "$RepoRoot",
  [string]$LiveDir      = "$LiveDir",
  [string]$RemoteName   = "$RemoteName",
  [string]$BranchName   = "$BranchName"
)
`$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path `$LiveDir | Out-Null
`$FlushLog = Join-Path `$LiveDir 'push-flush.log'
function LogF([string]`$m){ try{ `$ts=[DateTime]::UtcNow.ToString('o'); Add-Content -LiteralPath `$FlushLog -Value "[`$ts] `$m" -Encoding UTF8 }catch{} }

LogF "FLUSH-WRAP BOOT pid=`$PID"

`$health = Join-Path (Split-Path `$MyInvocation.MyCommand.Path -Parent) 'git-health.ps1'
`$pwsh   = (Get-Command pwsh -ErrorAction Stop).Source
`$healthArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',`$health,
  '-RepoRoot',`$RepoRoot,'-LiveDir',`$LiveDir,'-RemoteName',`$RemoteName,'-BranchName',`$BranchName)

`$hp = Start-Process -FilePath `$pwsh -ArgumentList `$healthArgs -WindowStyle Hidden -PassThru
`$hp.WaitForExit()
if(`$hp.ExitCode -ne 0){
  LogF "FLUSH-WRAP: abort push (git health fail, ec=`$($hp.ExitCode))"
  exit 0
}

`$pusher = "$PusherPath"
if(Test-Path -LiteralPath `$pusher){
  try{
    LogF "FLUSH-WRAP: running push-on-apply -RunOnce"
    & `$pusher -RunOnce
    `$ec = `$LASTEXITCODE
    LogF "FLUSH-WRAP: push-on-apply exited ec=`$ec"
    & "$SyncPath" -RepoRoot `$RepoRoot -LiveDir `$LiveDir -Reason "flush-wrap"
    exit 0
  } catch {
    LogF "FLUSH-WRAP EX: `$($_.Exception.Message)"
    exit 1
  }
}else{
  LogF "FLUSH-WRAP ERR: pusher not found at `$pusher"
  exit 2
}
"@
Write-Utf8NoBom -Path $WrapPath -Content $wrapSrc
OK "Wrote tools/ops/push-flush-wrap.ps1"

# --- 5) Doc updates (guards) ---
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

$healthDoc = @"
### Health Guard (no timers)

On each **apply/push** event the system runs a Git **health check**:
- If healthy → push proceeds.
- If disconnected you’ll see:
  - `ops/live/push-flush.log`: `GIT_HEALTH_FAIL reason=...`
  - `ops/live/GIT-DISCONNECTED.txt` with short repair instructions
  - `ops/live/git-health.json` (machine-readable status)

Fix the connection, then re-run the patch cycle.  
_sync-stamp: $stamp_
"@

$syncDoc = @"
### Sync Guard (no timers)

- **post-commit hook:** automatically pushes to `origin main` (event-driven).
- **pre-push hook:** runs the Health Guard and blocks bad pushes.
- **flush wrapper:** after router apply, performs an opportunistic sync.

Result: no background sweepers; you get immediate feedback and consistent state.  
_sync-stamp: $stamp_
"@

Patch-DocSection -Path $ReadmePath -Marker 'HEALTH-GUARD' -Body $healthDoc
Patch-DocSection -Path $ReadmePath -Marker 'SYNC-GUARD'   -Body $syncDoc
Patch-DocSection -Path $HandoverMd -Marker 'HEALTH-GUARD' -Body $healthDoc
Patch-DocSection -Path $HandoverMd -Marker 'SYNC-GUARD'   -Body $syncDoc
OK "Patched README.md & Handover with HEALTH/SYNC guard sections"

# --- 6) Commit & push ---
[void](GitRun @('add','-A'))
$needCommit = (GitRun @('diff','--cached','--quiet')).code -ne 0
if($needCommit){
  $msg = "ops: add health+sync guards, versioned hooks, and docs ($stamp)"
  $c = GitRun @('commit','-m',$msg,'--no-gpg-sign')
  if($c.code -ne 0){ ERR $c.err; throw "git commit failed" }
  OK "Committed changes."
}else{
  OK "No changes to commit."
}

Write-Host "Pushing to origin:$BranchName ..." -ForegroundColor Cyan
$push = GitRun @('push','-u','origin',$BranchName,'--force-with-lease')
if($push.code -ne 0){ ERR "git push failed: $($push.err)"; throw "Push failed" }
OK "Push complete."

# --- 7) Git version and upgrade hints (no auto-upgrade) ---
$gitVer = (GitRun @('--version')).out.Trim()
Write-Host ""
Write-Host "Git version detected: $gitVer" -ForegroundColor Cyan
Write-Host "If you want to upgrade Git on Windows:" -ForegroundColor Cyan
Write-Host "  winget upgrade --id Git.Git -e    # or:  choco upgrade git -y" -ForegroundColor Gray
Write-Host ""
Write-Host "DONE. Guards installed. On the next APPLY:" -ForegroundColor Cyan
Write-Host " - If disconnected: see ops/live/GIT-DISCONNECTED.txt + push-flush.log" -ForegroundColor Gray
Write-Host " - If healthy: push proceeds immediately (no timers)" -ForegroundColor Gray