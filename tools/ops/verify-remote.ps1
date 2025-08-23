param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch       = "main",
  [string]$RemoteName   = "origin",
  [string]$OldRemoteSha = "",
  [int]   $MaxWaitSec   = 600,
  [int]   $PollSec      = 2
)
$ErrorActionPreference='Stop'

function LogF([string]$m){
  try{
    $ts=[DateTime]::UtcNow.ToString('o')
    Add-Content -LiteralPath (Join-Path $LiveDir 'push-flush.log') -Value "[$ts] $m" -Encoding UTF8
  }catch{}
}
function Sha256Bytes([byte[]]$bytes){
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try{ return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
  finally{ $sha.Dispose() }
}
# FIX HERE: use $argv instead of $args so we don't shadow PowerShell's automatic $args.
function GitExec([string[]]$argv){
  try{
    $text = & git @argv 2>&1
    $code = $LASTEXITCODE
    $out  = ($text | Out-String)
    return @{ out=$out; err=''; code=$code }
  } catch {
    return @{ out=''; err=$_.Exception.Message; code=9001 }
  }
}
function GitOutSafe([string[]]$argv,[string]$tag){
  $r = GitExec $argv
  if($r.code -ne 0){ LogF ("VERIFY_GIT_ERR tag={0} code={1} out={2}" -f $tag,$r.code, ($r.out.Trim() -replace "`r|`n",' ')) }
  else{ LogF ("VERIFY_GIT_OK tag={0} out={1}" -f $tag, ($r.out.Trim() -replace "`r|`n",' ')) }
  return $r
}
function GitBlobBytes([string]$commitSha,[string]$relPath){
  $spec = ('{0}:{1}' -f $commitSha, $relPath)
  $quotedSpec = '"' + ($spec -replace '"','""') + '"'
  $psi=[System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName='git'
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $psi.CreateNoWindow=$true
  $psi.WorkingDirectory=$RepoRoot
  $psi.Arguments = 'show ' + $quotedSpec
  $p=[System.Diagnostics.Process]::Start($psi)
  $ms=New-Object System.IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit() | Out-Null
  if($p.ExitCode -ne 0){
    $err = $p.StandardError.ReadToEnd()
    LogF ("VERIFY_GIT_ERR tag=git-show code={0} err={1}" -f $p.ExitCode, ($err -replace "`r|`n",' '))
    return $null
  }
  $ms.ToArray()
}
function FetchRawBytes([string]$url){
  $tmp=[System.IO.Path]::GetTempFileName()
  try{
    Invoke-WebRequest -Uri $url -TimeoutSec 30 -Headers @{ 'Cache-Control'='no-cache' } -OutFile $tmp | Out-Null
    [System.IO.File]::ReadAllBytes($tmp)
  } catch { $null } finally { try{ Remove-Item -Force $tmp -ErrorAction SilentlyContinue }catch{} }
}
function RawUrl([string]$owner,[string]$repo,[string]$branch,[string]$relPath){
  $parts = $relPath -split '[\\/]' | Where-Object { $_ -ne '' } | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  "https://raw.githubusercontent.com/$owner/$repo/$branch/" + ($parts -join '/')
}

Push-Location -LiteralPath $RepoRoot
try {
  try {
    $gitPath = (Get-Command git -ErrorAction Stop).Source
    LogF ("VERIFY_ENV git={0}" -f $gitPath)
  } catch { LogF ("VERIFY_ENV_NO_GIT msg={0}" -f $_.Exception.Message); exit 1 }

  $isInside = $false
  $p1 = GitOutSafe @('rev-parse','--is-inside-work-tree') 'rev-parse-is-inside'
  if($p1.code -eq 0 -and $p1.out.Trim().ToLowerInvariant() -eq 'true'){ $isInside=$true }
  if(-not $isInside){
    $p2 = GitOutSafe @('rev-parse','--git-dir') 'rev-parse-git-dir'
    if($p2.code -eq 0 -and -not [string]::IsNullOrWhiteSpace($p2.out)){
      $gitDir = $p2.out.Trim(); if(-not (Split-Path $gitDir -IsAbsolute)){ $gitDir = Join-Path $RepoRoot $gitDir }
      if(Test-Path -LiteralPath $gitDir){ $isInside = $true }
      LogF ("VERIFY_PROBE git-dir={0} exists={1}" -f $gitDir, (Test-Path -LiteralPath $gitDir))
    }
  }
  if(-not $isInside){
    $p3 = GitOutSafe @('rev-parse','--show-toplevel') 'rev-parse-show-toplevel'
    if($p3.code -eq 0 -and -not [string]::IsNullOrWhiteSpace($p3.out)){
      $top=[System.IO.Path]::GetFullPath($p3.out.Trim()); $root=[System.IO.Path]::GetFullPath($RepoRoot)
      LogF ("VERIFY_PROBE toplevel={0} root={1}" -f $top,$root)
      if($top -eq $root){ $isInside=$true }
    }
  }
  if(-not $isInside){
    $dotGit = Join-Path $RepoRoot '.git'
    LogF ("VERIFY_PROBE dotgit={0} exists={1}" -f $dotGit,(Test-Path -LiteralPath $dotGit))
    if(Test-Path -LiteralPath $dotGit){ $isInside=$true }
  }
  if(-not $isInside){ LogF "VERIFY_ENV_NOT_WORKTREE (no probe succeeded)"; exit 1 } else { LogF "VERIFY_ENV_WORKTREE_OK" }

  $localR  = GitOutSafe @('rev-parse','HEAD') 'rev-parse-HEAD'
  $localSha= $localR.out.Trim()
  $remoteR = GitOutSafe @('ls-remote',$RemoteName,("refs/heads/$Branch")) 'ls-remote'
  $remote  = $remoteR.out.Trim()
  $remoteSha = if([string]::IsNullOrWhiteSpace($remote)){ '' } else { ($remote -split '\s+')[0] }

  LogF "VERIFY_BEGIN local=$localSha remote=$remoteSha branch=$Branch repo=$Owner/$Repo"

  if([string]::IsNullOrWhiteSpace($remoteSha) -or $remoteSha -ne $localSha){
    LogF "VERIFY_FAIL_REF local=$localSha remote=$remoteSha"
    exit 2
  }

  $changed = @()
  if($OldRemoteSha -and $OldRemoteSha.Length -ge 7){
    $diffR = GitOutSafe @('diff','--name-only',$OldRemoteSha,$localSha) 'diff-range'
    $changed = ($diffR.out -split "`r?`n")
  } else {
    $treeR = GitOutSafe @('diff-tree','--no-commit-id','--name-only','-r',$localSha) 'diff-tree'
    $changed = ($treeR.out -split "`r?`n")
  }
  $changed = @($changed | Where-Object { $_ -and $_ -notmatch '^(Library/|ops/live/)' })
  LogF ("VERIFY_CHANGED_COUNT={0}" -f $changed.Count)
  if($changed.Count -gt 0){ LogF ("VERIFY_CHANGED_SAMPLE={0}" -f (($changed | Select-Object -First 10) -join ', ')) }

  if($changed.Count -eq 0){ LogF "VERIFY_NO_CHANGED_FILES local=$localSha"; exit 0 }

  $t0=[DateTime]::UtcNow; $allOk=$true
  foreach($rel in $changed){
    $blob = GitBlobBytes $localSha $rel
    if($null -eq $blob){ LogF ("VERIFY_SKIP path={0} reason=blob-missing" -f $rel); $allOk=$false; continue }
    $expectSha = Sha256Bytes $blob
    $url = RawUrl $Owner $Repo $Branch $rel
    $okFile=$false
    while(-not $okFile){
      $elapsed = [int]([DateTime]::UtcNow - $t0).TotalSeconds
      if($elapsed -ge $MaxWaitSec){ LogF ("VERIFY_FAIL_CDN_TIMEOUT path={0} want={1} waited={2}s" -f $rel,$expectSha,$elapsed); $allOk=$false; break }
      $raw = FetchRawBytes $url
      if($null -eq $raw){ LogF ("VERIFY_WAIT_CDN path={0} status=NOFETCH elapsed={1}/{2}s" -f $rel,$elapsed,$MaxWaitSec); Start-Sleep -Seconds $PollSec; continue }
      $gotSha = Sha256Bytes $raw
      if($gotSha -eq $expectSha){ LogF ("VERIFY_OK path={0} sha={1} elapsed={2}s" -f $rel,$gotSha,$elapsed); $okFile=$true }
      else{ LogF ("VERIFY_WAIT_CDN path={0} status=HASH_MISMATCH want={1} got={2} elapsed={3}/{4}s" -f $rel,$expectSha,$gotSha,$elapsed,$MaxWaitSec); Start-Sleep -Seconds $PollSec }
    }
  }
  if($allOk){ LogF "VERIFY_STRICT_OK commit=$localSha"; exit 0 } else { LogF "VERIFY_STRICT_FAIL commit=$localSha"; exit 3 }
}
catch {
  $t = $_.Exception.GetType().FullName
  LogF ("VERIFY_EX type={0} msg={1}" -f $t, $_.Exception.Message)
  if ($_.InvocationInfo) { LogF ("VERIFY_EX_AT {0}" -f $_.InvocationInfo.PositionMessage.Replace("`r"," ").Replace("`n"," ")) }
  exit 1
}
finally { Pop-Location }