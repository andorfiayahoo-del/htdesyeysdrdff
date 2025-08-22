param(
  [string]$RepoRoot,
  [string]$LiveDir,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch       = 'main',
  [string]$RemoteName   = 'origin',
  [string]$OldRemoteSha = '',          # optional: remote SHA before push (for changed-file range)
  [int]   $MaxWaitSec   = 600,         # max time to wait for RAW/Blob propagation
  [int]   $PollSec      = 2            # polling interval for RAW URLs
)
$ErrorActionPreference='Stop'

# --- helpers ---
function LogF([string]$m){
  try{
    $ts=[DateTime]::UtcNow.ToString('o')
    Add-Content -LiteralPath (Join-Path $LiveDir 'push-flush.log') -Value "[$ts] $m" -Encoding UTF8
  }catch{}
}
function Sha256Bytes([byte[]]$bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{ return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
  finally{ $sha.Dispose() }
}
function GitExec([string[]]$args){
  $psi=[System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName='git'; $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $psi.WorkingDirectory = $RepoRoot
  $psi.Arguments=[string]::Join(' ', ($args | ForEach-Object { if($_ -match '[\s"]'){'"'+($_ -replace '"','""')+'"'}else{$_}}))
  $p=[System.Diagnostics.Process]::Start($psi)
  $out=$p.StandardOutput.ReadToEnd(); $err=$p.StandardError.ReadToEnd(); $p.WaitForExit() | Out-Null
  return @{out=$out;err=$err;code=$p.ExitCode}
}
function GitOut([string[]]$args){ (GitExec $args).out }
function GitCode([string[]]$args){ (GitExec $args).code }

function GitBlobBytes([string]$commitSha,[string]$relPath){
  # Use 'git show <sha>:<path>' and capture bytes
  $psi=[System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName='git'; $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true
  $psi.WorkingDirectory=$RepoRoot
  $psi.Arguments=[string]::Join(' ',@('show',("$commitSha:`"$relPath`"")))
  $p=[System.Diagnostics.Process]::Start($psi)
  $ms=New-Object System.IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit() | Out-Null
  if($p.ExitCode -ne 0){ return $null }
  return $ms.ToArray()
}
function FetchRawBytes([string]$url){
  try{
    $tmp=[System.IO.Path]::GetTempFileName()
    try{
      $wc = New-Object System.Net.WebClient
      $wc.Headers['Cache-Control']='no-cache'
      $wc.DownloadFile($url,$tmp)
      return [System.IO.File]::ReadAllBytes($tmp)
    } finally { if(Test-Path $tmp){ Remove-Item -Force $tmp } }
  } catch { return $null }
}
function RawUrl([string]$owner,[string]$repo,[string]$branch,[string]$relPath){
  $parts = $relPath -split '[\\/]' | Where-Object { $_ -ne '' } | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  return "https://raw.githubusercontent.com/$owner/$repo/$branch/" + ($parts -join '/')
}

# --- begin verification ---
Push-Location -LiteralPath $RepoRoot
try{
  $localSha   = (GitOut @('rev-parse','HEAD')).Trim()
  $remoteLine = (GitOut @('ls-remote',$RemoteName,("refs/heads/$Branch"))).Trim()
  $remoteSha  = if([string]::IsNullOrWhiteSpace($remoteLine)){ '' } else { ($remoteLine -split '\s+')[0] }

  LogF "VERIFY_BEGIN local=$localSha remote=$remoteSha branch=$Branch repo=$Owner/$Repo"

  if([string]::IsNullOrWhiteSpace($remoteSha) -or $remoteSha -ne $localSha){
    LogF "VERIFY_FAIL_REF local=$localSha remote=$remoteSha"
    exit 2
  }

  # Determine changed files (prefer OldRemoteSha; else last commit only)
  $changed = @()
  if($OldRemoteSha -and $OldRemoteSha.Length -ge 7){
    $changed = (GitOut @('diff','--name-only',$OldRemoteSha,$localSha)) -split "`r?`n"
  } else {
    $changed = (GitOut @('diff-tree','--no-commit-id','--name-only','-r',$localSha)) -split "`r?`n"
  }
  $changed = @($changed | Where-Object { $_ -and $_ -notmatch '^(Library/|ops/live/)' })

  if($changed.Count -eq 0){
    LogF "VERIFY_NO_CHANGED_FILES local=$localSha"
    exit 0
  }

  $t0 = [DateTime]::UtcNow
  $allOk = $true

  foreach($rel in $changed){
    $blob = GitBlobBytes $localSha $rel
    if($null -eq $blob){
      LogF ("VERIFY_SKIP path={0} reason=blob-missing" -f $rel)
      continue
    }
    $expectSha = Sha256Bytes $blob
    $url = RawUrl $Owner $Repo $Branch $rel

    $okFile=$false
    while(-not $okFile){
      $elapsed = [int]([DateTime]::UtcNow - $t0).TotalSeconds
      if($elapsed -ge $MaxWaitSec){
        LogF ("VERIFY_FAIL_CDN_TIMEOUT path={0} want={1} waited={2}s" -f $rel,$expectSha,$elapsed)
        $allOk=$false
        break
      }

      $raw = FetchRawBytes $url
      if($null -eq $raw){
        LogF ("VERIFY_WAIT_CDN path={0} status=NOFETCH elapsed={1}/{2}s" -f $rel,$elapsed,$MaxWaitSec)
        Start-Sleep -Seconds $PollSec
        continue
      }

      # Compare byte-for-byte to blob (handles CRLF because blob is LF-normalized)
      $gotSha = Sha256Bytes $raw
      if($gotSha -eq $expectSha){
        LogF ("VERIFY_OK path={0} sha={1} elapsed={2}s" -f $rel,$gotSha,$elapsed)
        $okFile=$true
      } else {
        LogF ("VERIFY_WAIT_CDN path={0} status=HASH_MISMATCH want={1} got={2} elapsed={3}/{4}s" -f $rel,$expectSha,$gotSha,$elapsed,$MaxWaitSec)
        Start-Sleep -Seconds $PollSec
      }
    }
  }

  if($allOk){
    LogF "VERIFY_STRICT_OK commit=$localSha"
    exit 0
  } else {
    LogF "VERIFY_STRICT_FAIL commit=$localSha"
    exit 3
  }
}
finally { Pop-Location }