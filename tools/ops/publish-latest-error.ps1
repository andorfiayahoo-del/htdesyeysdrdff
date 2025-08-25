# tools/ops/publish-latest-error.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [string]$LiveDir  = (Join-Path $RepoRoot 'ops\live')
)
$ErrorActionPreference = 'Continue'
trap { Write-Warning ("publisher: " + $_.Exception.Message); continue }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
if(!(Test-Path $LiveDir)){ New-Item -ItemType Directory -Path $LiveDir | Out-Null }
$errFiles = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
$txFiles  = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
$rid = 'unknown'; $errTxt = @(); $txTail = @()
$errPath = ''; $errLine = ''; $txPath = ''; $errTxtPath = ''
if($errFiles){ $err = $errFiles[0]; $rid = ($err.BaseName -replace '^error_',''); $errTxt = Get-Content $err.FullName -ErrorAction SilentlyContinue; $errTxtPath = $err.FullName }
if($txFiles){ $tx = $txFiles[0]; if($rid -eq 'unknown'){ $rid = ($tx.BaseName -replace '^transcript_','') } ; $txTail = Get-Content $tx.FullName -Tail 120 -ErrorAction SilentlyContinue; $txPath = $tx.FullName }
$fullErr = ($errTxt -join "`n")
$m = [regex]::Match($fullErr, 'ParserError:\s+(.+?):(\d+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
if($m.Success){ $errPath = $m.Groups[1].Value; $errLine = $m.Groups[2].Value }
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Latest Error Snapshot")
$md.Add("")
$md.Add("**RID:** $rid  ")
$md.Add("**Status:** ERROR  ")
if($errPath -ne ''){ $md.Add("**File:** $errPath  ") }
if($errLine -ne ''){ $md.Add("**Line:** $errLine  ") }
if($errTxt -and $errTxt.Count -gt 0){ $md.Add("**Error:** " + ($errTxt -join " ") + "  ") } else { $md.Add("**Error:** (none captured)  ") }
$md.Add("")
$md.Add("```text")
foreach($l in $txTail){ $md.Add($l) }
$md.Add("```")
$out = Join-Path $LiveDir 'latest-error.md'
Write-LF $out $md.ToArray()
$head = '' ; try { $head = (git -C "$RepoRoot" rev-parse HEAD).Trim() } catch { }
$ptr = [pscustomobject]@{ rid = $rid; status = "ERROR"; head = $head; file = $errPath; line = $errLine; files = [pscustomobject]@{ error_md = $out; transcript = $txPath; error_txt = $errTxtPath } }
$json = ($ptr | ConvertTo-Json -Depth 6)
Write-LF (Join-Path $LiveDir 'latest-pointer.json') @($json)
exit 0