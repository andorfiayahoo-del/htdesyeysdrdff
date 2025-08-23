param(
  [string]$RepoRoot,
  [string]$RelPath,
  [string]$Owner,
  [string]$Repo,
  [string]$Branch = 'main',
  [switch]$NoNormalizeWorkingFile,
  [switch]$SkipRaw,
  [switch]$SkipWorking
)
$ErrorActionPreference = 'Stop'
function Sha256Bytes([byte[]]$bytes){ $sha=[System.Security.Cryptography.SHA256]::Create(); try{ ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant() } finally{ $sha.Dispose() } }
function RawUrl([string]$owner,[string]$repo,[string]$branch,[string]$relPath){ $parts = $relPath -split '[\\/ ]+' | Where-Object { $_ -ne "" } | ForEach-Object { [System.Uri]::EscapeDataString($_) }; "https://raw.githubusercontent.com/$owner/$repo/$branch/" + ($parts -join "/") }
function ReadFileBytes([string]$abs){ if(Test-Path -LiteralPath $abs){ [System.IO.File]::ReadAllBytes($abs) } else { $null } }
function GitBlobBytes([string]$repoRoot,[string]$rev,[string]$rel){
  $spec = ("{0}:{1}" -f $rev, $rel)
  $psi=[System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName="git"; $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true; $psi.WorkingDirectory=$repoRoot
  $psi.Arguments = 'show "' + ($spec -replace '"','""') + '"'
  $p=[System.Diagnostics.Process]::Start($psi)
  $ms=New-Object System.IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit() | Out-Null
  if($p.ExitCode -ne 0){ throw "git show failed: " + $p.StandardError.ReadToEnd() }
  $ms.ToArray()
}
Push-Location -LiteralPath $RepoRoot
try {
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "Not a git work tree: $RepoRoot" }
  $head = (& git rev-parse HEAD 2>$null).Trim()
  $blob = GitBlobBytes $RepoRoot $head $RelPath
  $blobSha = Sha256Bytes $blob
  $abs = Join-Path $RepoRoot $RelPath

  # Working file (optional)
  $work = $null; $workSha = "(skipped)"
  if (-not $SkipWorking) {
    $work = ReadFileBytes $abs
    $workSha = if($work){ Sha256Bytes $work } else { "(missing)" }
  }

  # RAW (optional)
  $rawSha = "(skipped)"
  $effectiveSkipRaw = $SkipRaw -or [string]::IsNullOrWhiteSpace($Owner) -or [string]::IsNullOrWhiteSpace($Repo)
  if (-not $effectiveSkipRaw) {
    $url = RawUrl $Owner $Repo $Branch $RelPath
    $tmp=[System.IO.Path]::GetTempFileName()
    try {
      Invoke-WebRequest -Uri $url -TimeoutSec 30 -Headers @{ "Cache-Control"="no-cache" } -OutFile $tmp | Out-Null
      $raw = [System.IO.File]::ReadAllBytes($tmp)
      $rawSha = Sha256Bytes $raw
    } finally { try{ Remove-Item -Force $tmp -ErrorAction SilentlyContinue }catch{} }
  }

  $bw = $true
  if (-not $SkipWorking) {
    $bw = ($work -ne $null) -and ($workSha -eq $blobSha)
  }
  $br = $true
  if (-not $effectiveSkipRaw) {
    $br = ($rawSha -eq $blobSha)
  }

  Write-Host ("RepoRoot             : {0}" -f $RepoRoot)
  Write-Host ("RelPath              : {0}" -f $RelPath)
  Write-Host ("HEAD                 : {0}" -f $head)
  Write-Host ("Blob SHA256          : {0}" -f $blobSha)
  Write-Host ("Working-file SHA256   : {0}" -f $workSha)
  Write-Host ("CDN RAW SHA256       : {0}" -f $rawSha)
  if ($SkipWorking) { Write-Host "Blob vs Working       : (skipped)" } else { Write-Host ("Blob vs Working       : {0}" -f ($(if($bw){"MATCH ✅"} else {"MISMATCH ❌"}))) }
  if ($effectiveSkipRaw) { Write-Host "Blob vs RAW           : (skipped)" } else { Write-Host ("Blob vs RAW           : {0}" -f ($(if($br){"MATCH ✅"} else {"MISMATCH ❌"}))) }

  if(((-not $SkipWorking) -and -not $bw) -or ((-not $effectiveSkipRaw) -and -not $br)){ exit 3 } else { exit 0 }
}
catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  exit 1
}
finally { Pop-Location }
