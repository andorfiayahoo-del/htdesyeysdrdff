param(
  [Parameter(Mandatory=$true)][string]$RelPath,         # e.g. tools/ops/cdn-test.ps1 (forward slashes ok)
  [string]$RepoRoot = (Get-Location).Path,
  [string]$Owner    = "",
  [string]$Repo     = "",
  [string]$Branch   = "main",
  [switch]$NoNormalizeWorkingFile                      # by default CRLF->LF before hashing working file
)

$ErrorActionPreference = "Stop"

function Get-Sha256Hex([byte[]]$bytes){
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try { ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLower() }
  finally { $sha.Dispose() }
}

function Get-GitBlobBytes([string]$repoRoot,[string]$rel){
  # HEAD:"<rel>" using raw stdout bytes so we don’t alter line endings
  $spec = 'HEAD:' + ($rel -replace '"','""')
  $psi=[System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName='git'
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $psi.CreateNoWindow=$true
  $psi.WorkingDirectory=$repoRoot
  $psi.Arguments='show "' + $spec + '"'
  $p=[System.Diagnostics.Process]::Start($psi)
  $ms=New-Object System.IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms); $p.WaitForExit() | Out-Null
  if($p.ExitCode -ne 0){ throw "git show failed: " + $p.StandardError.ReadToEnd() }
  $ms.ToArray()
}

function Get-RawUrl([string]$owner,[string]$repo,[string]$branch,[string]$rel){
  $parts = $rel -split '[\\/]' | Where-Object { $_ -ne '' } | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  "https://raw.githubusercontent.com/$owner/$repo/$branch/" + ($parts -join '/')
}

# --- Preflight ---
Push-Location -LiteralPath $RepoRoot
try{
  if(-not (Test-Path -LiteralPath '.git')){ throw "No .git folder at $RepoRoot" }
  & git rev-parse --is-inside-work-tree *> $null
  if($LASTEXITCODE -ne 0){ throw "Git says this is not a work tree: $RepoRoot" }

  $head = (& git rev-parse HEAD 2>&1).Trim()

  # --- A) Blob hash (exact committed bytes) ---
  $blobBytes = Get-GitBlobBytes $RepoRoot $RelPath
  $blobSha   = Get-Sha256Hex $blobBytes

  # --- B) Working-file hash (normalized by default) ---
  $fsPath = Join-Path $RepoRoot ($RelPath -replace '/','\')
  $wfSha  = $null
  $workStatus = "missing"
  if(Test-Path -LiteralPath $fsPath){
    $workStatus = "present"
    if($NoNormalizeWorkingFile){
      $wfBytes = [System.IO.File]::ReadAllBytes($fsPath)
    } else {
      $txt   = Get-Content -LiteralPath $fsPath -Raw
      $lf    = $txt -replace "`r`n","`n"
      $wfBytes = [System.Text.Encoding]::UTF8.GetBytes($lf)
    }
    $wfSha = Get-Sha256Hex $wfBytes
  }

  # --- C) CDN RAW hash (optional unless Owner/Repo provided) ---
  $rawSha = $null
  if($Owner -and $Repo){
    $url = Get-RawUrl $Owner $Repo $Branch $RelPath
    $tmp=[System.IO.Path]::GetTempFileName()
    try{
      Invoke-WebRequest -Uri $url -TimeoutSec 30 -Headers @{ 'Cache-Control'='no-cache' } -OutFile $tmp | Out-Null
      $rawSha = Get-Sha256Hex ([System.IO.File]::ReadAllBytes($tmp))
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  }

  # --- Report ---
  "RepoRoot            : $RepoRoot"
  "RelPath             : $RelPath"
  "HEAD                : $head"
  "Blob SHA256         : $blobSha"
  if($wfSha){ "Working-file SHA256  : $wfSha" } else { "Working-file        : $workStatus" }
  if($rawSha){ "CDN RAW SHA256      : $rawSha" } else { "CDN RAW             : (skipped)" }

  if($wfSha){ "Blob vs Working      : " + ($(if($blobSha -eq $wfSha){'MATCH ✅'}else{'MISMATCH ❌'})) }
  if($rawSha){ "Blob vs RAW          : " + ($(if($blobSha -eq $rawSha){'MATCH ✅'}else{'MISMATCH ❌'})) }

  # Exit codes: 0 OK, 3 any mismatch, 2 missing working file, 1 other errors
  $mismatch = ($wfSha -and $blobSha -ne $wfSha) -or ($rawSha -and $blobSha -ne $rawSha)
  if($mismatch){ exit 3 }
  elseif(-not $wfSha){ exit 2 }
  else{ exit 0 }
}
finally { Pop-Location }
