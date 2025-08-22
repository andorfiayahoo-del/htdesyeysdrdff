param([string]$RepoRoot="C:\Users\ander\My project",[string]$LiveDir="C:\Users\ander\My project\ops\live",[string]$RemoteName="origin",[string]$BranchName="main")
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $LiveDir | Out-Null
$FlushLog=Join-Path $LiveDir 'push-flush.log'
function LogF([string]$m){ try{ $ts=[DateTime]::UtcNow.ToString('o'); Add-Content -LiteralPath $FlushLog -Value "[$ts] $m" -Encoding UTF8 }catch{} }
LogF "FLUSH-WRAP BOOT pid=$PID"
$here=Split-Path $MyInvocation.MyCommand.Path -Parent
$health=Join-Path $here 'git-health.ps1'
$sync=Join-Path $here 'git-sync.ps1'
$pusher=Join-Path $here 'push-on-apply.ps1'
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$healthArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$health,'-RepoRoot',$RepoRoot,'-LiveDir',$LiveDir,'-RemoteName',$RemoteName,'-BranchName',$BranchName)
$hp=Start-Process -FilePath $pwsh -ArgumentList $healthArgs -WindowStyle Hidden -PassThru
$hp.WaitForExit()
if($hp.ExitCode -ne 0){ LogF "FLUSH-WRAP: abort push (git health fail, ec=$($hp.ExitCode))"; exit 0 }
if(Test-Path -LiteralPath $pusher){
  try{
    LogF "FLUSH-WRAP: running push-on-apply -RunOnce"
    & $pusher -RunOnce
    $ec=$LASTEXITCODE
    LogF "FLUSH-WRAP: push-on-apply exited ec=$ec"
    & $sync -RepoRoot $RepoRoot -LiveDir $LiveDir -Reason "flush-wrap"
    exit 0
  } catch { LogF "FLUSH-WRAP EX: $($_.Exception.Message)"; exit 1 }
}else{ LogF "FLUSH-WRAP ERR: pusher not found at $pusher"; exit 2 }