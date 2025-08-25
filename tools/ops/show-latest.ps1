param(
  [string]$RepoRoot = "C:\Users\ander\My project"
)
$ErrorActionPreference = "Stop"
$Live = Join-Path $RepoRoot "ops\live"
$ptr  = Join-Path $Live "latest-pointer.json"
$md   = Join-Path $Live "latest-error.md"

if(!(Test-Path $Live)){ Write-Warning "No ops/live dir at $Live"; exit 0 }
if(!(Test-Path $ptr) -and (Test-Path $md)){ Write-Host "latest-error.md:`n"; Get-Content $md -First 60; exit 0 }
if(!(Test-Path $ptr)){ Write-Warning "No latest-pointer.json found."; exit 0 }

$P = Get-Content $ptr -Raw | ConvertFrom-Json
Write-Host ("RID    : " + $P.rid)
Write-Host ("Status : " + $P.status)
Write-Host ("Head   : " + $P.head)
Write-Host ("File   : " + $P.file)
Write-Host ("Line   : " + $P.line)
Write-Host ("error_md  : " + $P.files.error_md)
Write-Host ("transcript: " + $P.files.transcript)
Write-Host ("error_txt : " + $P.files.error_txt)

$ridMd = ''
if(Test-Path $md){
  try{
    $mdText = Get-Content $md -Raw
    $mRID = [regex]::Match($mdText, '20\d{6}T\d{6}\.\d+Z-[0-9a-f]{32}', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($mRID.Success){ $ridMd = $mRID.Value }
  } catch { }
}

if(Test-Path $md){
  Write-Host "`n--- latest-error.md (head) ---"
  Get-Content $md -First 40
}

if($ridMd -and ($ridMd -ne $P.rid)){
  Write-Warning ("Note: latest-error.md RID (" + $ridMd + ") differs from pointer RID (" + $P.rid + "). Showing transcript tail for pointer RID.")
  if($P.files.transcript -and (Test-Path $P.files.transcript)){
    Write-Host "`n--- transcript tail (" + $P.rid + ") ---"
    Get-Content $P.files.transcript -Tail 60
  }
}