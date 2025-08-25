# tools/ops/publish-latest-error.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [string]$LiveDir  = (Join-Path $RepoRoot 'ops\live')
)
$ErrorActionPreference = 'Stop'
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
if(!(Test-Path $LiveDir)){ throw "LiveDir not found: $LiveDir" }
$errFiles = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
$txFiles  = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
$rid = 'unknown'; $errTxt = @(); $txTail = @()
if($errFiles){
  $err = $errFiles[0]; $rid = ($err.BaseName -replace '^error_', '')
  $errTxt = Get-Content $err.FullName -ErrorAction SilentlyContinue
}
if($txFiles){
  $tx = $txFiles[0]
  if($rid -eq 'unknown'){ $rid = ($tx.BaseName -replace '^transcript_', '') }
  $txTail = Get-Content $tx.FullName -Tail 80 -ErrorAction SilentlyContinue
}
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Latest Error Snapshot")
$md.Add("")
$md.Add("**RID:** $rid  ")
$md.Add("**Status:** ERROR  ")
if($errTxt -and $errTxt.Count -gt 0){ $md.Add("**Error:** " + ($errTxt -join " ") + "  ") } else { $md.Add("**Error:** (none captured)  ") }
$md.Add("")
$md.Add("```text")
foreach($l in $txTail){ $md.Add($l) }
$md.Add("```")
$out = Join-Path $LiveDir 'latest-error.md'
Write-LF $out $md.ToArray()
Write-Output $out