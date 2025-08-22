param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$RemoteName = "origin",
  [string]$BranchName = "main"
)
$ErrorActionPreference = "Stop"
$FlushLog = Join-Path $LiveDir "push-flush.log"
$StatusJ  = Join-Path $LiveDir "git-health.json"
$Sentinel = Join-Path $LiveDir "GIT-DISCONNECTED.txt"
function LogF([string]$m){ try{ $ts=[DateTime]::UtcNow.ToString("o"); Add-Content -LiteralPath $FlushLog -Value "[$ts] $m" -Encoding UTF8 }catch{} }
function JsonOut([hashtable]$obj){ try{ ($obj|ConvertTo-Json -Depth 6)|Set-Content -LiteralPath $StatusJ -Encoding UTF8 }catch{} }
$status=@{ utc=[DateTime]::UtcNow.ToString("o"); repoRoot=$RepoRoot; remoteName=$RemoteName; branchName=$BranchName; ok=$true; checks=@(); failureReason=$null }
function AddCheck([string]$n,[bool]$ok,[string]$d){ $status.checks += @{name=$n;ok=$ok;detail=$d}; if(-not $ok){ $status.ok=$false } }
function Fail([string]$n,[string]$d,[string]$r){ AddCheck $n $false $d; $status.failureReason=$r }
if(-not (Test-Path -LiteralPath $RepoRoot)){ Fail "RepoRootExists" "Missing $RepoRoot" "RepoRoot missing" } else { AddCheck "RepoRootExists" $true "ok" }
if($status.ok){
  Push-Location -LiteralPath $RepoRoot
  try{
    $isWT = & git rev-parse --is-inside-work-tree 2>$null
    if($LASTEXITCODE -ne 0 -or ($isWT|Out-String).Trim() -ne "true"){ Fail "IsInsideWorkTree" "Not a git work tree" "Not a git work tree" } else { AddCheck "IsInsideWorkTree" $true "ok" }
    if($status.ok){
      $remoteUrl = & git remote get-url $RemoteName 2>$null
      if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($remoteUrl|Out-String).Trim())){ Fail "RemotePresent" "Remote '$RemoteName' not set" "Remote not set" } else { AddCheck "RemotePresent" $true (($remoteUrl|Out-String).Trim()) }
    }
    if($status.ok){
      & git ls-remote --heads $RemoteName $BranchName *> $null
      if($LASTEXITCODE -ne 0){ Fail "RemoteReachable" "ls-remote failed" "Remote unreachable" } else { AddCheck "RemoteReachable" $true "ok" }
    }
    # no push --dry-run here
  } finally { Pop-Location }
}
JsonOut $status
if($status.ok){
  LogF "GIT_HEALTH_OK remote=$RemoteName branch=$BranchName"
  if(Test-Path -LiteralPath $Sentinel){ try{ Remove-Item -LiteralPath $Sentinel -Force }catch{} }
  exit 0
}else{
  LogF "GIT_HEALTH_FAIL reason=$($status.failureReason)"
  try{
    $reason=$status.failureReason
    $content="Git repo appears **disconnected** (reason: $reason).`r`n`r`nWhat to do:`r`n  1) Open pwsh in `"$RepoRoot`".`r`n  2) Run your saved **Repair/Reconnect** snippet (or ask assistant).`r`n  3) Re-run the patch cycle; health will go green.`r`n`r`n(Written by tools/ops/git-health.ps1 on each apply/push event.)`r`n"
    Set-Content -LiteralPath $Sentinel -Encoding UTF8 -Value $content
  }catch{}
  exit 2
}