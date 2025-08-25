# tools/ops/publish-latest-error.ps1
param(
  [string]$RepoRoot = "C:\Users\ander\My project",
  [string]$LiveDir  = (Join-Path $RepoRoot "ops\live"),
  [string]$Rid
)
$ErrorActionPreference = "Continue"
trap { Write-Warning ("publisher: " + $_.Exception.Message); continue }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }

try {
  if(!(Test-Path $LiveDir)){ New-Item -ItemType Directory -Path $LiveDir | Out-Null }
  $txFiles  = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
  $errFiles = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt'      -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending

  $rid = 'unknown'; $txPath = ''; $errTxt = @(); $errTxtPath = ''

  if($Rid){
    $rid = $Rid
    $txCand = Join-Path $LiveDir ("transcript_" + $rid + ".log")
    if(Test-Path $txCand){ $txPath = $txCand }
    $errCand = Join-Path $LiveDir ("error_" + $rid + ".txt")
    if(Test-Path $errCand){ $errTxt = Get-Content $errCand -ErrorAction SilentlyContinue; $errTxtPath = $errCand }
  } else {
    if($txFiles){
      $tx = $txFiles[0]; $txPath = $tx.FullName; $rid = ($tx.BaseName -replace '^transcript_','')
    }
    if($rid -eq 'unknown' -and $errFiles){
      $err = $errFiles[0]; $errTxt = Get-Content $err.FullName -ErrorAction SilentlyContinue; $errTxtPath = $err.FullName
      $rid = ($err.BaseName -replace '^error_','')
    } else {
      $errByRid = Join-Path $LiveDir ("error_" + $rid + ".txt")
      if(Test-Path $errByRid){
        $errTxt = Get-Content $errByRid -ErrorAction SilentlyContinue; $errTxtPath = $errByRid
      } elseif($errFiles){
        $err = $errFiles[0]; $errTxt = Get-Content $err.FullName -ErrorAction SilentlyContinue; $errTxtPath = $err.FullName
      }
    }
  }

  $txTail = @(); if($txPath -and (Test-Path $txPath)){ $txTail = Get-Content $txPath -Tail 120 -ErrorAction SilentlyContinue }
  $fullErr = ($errTxt -join "`n")
  $errPath = ''; $errLine = ''

  $m  = [regex]::Match($fullErr, 'ParserError:\s+(.+?):(\d+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if($m.Success){ $errPath = $m.Groups[1].Value; $errLine = $m.Groups[2].Value }
  if(-not $m.Success){
    $m2 = [regex]::Match($fullErr, '(?m)^\s*At\s+(.+?):(\d+)\s+char:', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m2.Success){ $errPath = $m2.Groups[1].Value; $errLine = $m2.Groups[2].Value }
  }
  if([string]::IsNullOrWhiteSpace($errLine)){
    $m3 = [regex]::Match($fullErr, '(?m)^\s*Line\s*\|\s*(\d+)\s*\|', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m3.Success){ $errLine = $m3.Groups[1].Value }
  }
  if([string]::IsNullOrWhiteSpace($errPath) -and $txTail){
    foreach($tl in $txTail){
      $mExec = [regex]::Match($tl, 'EXEC:\s+pwsh\s+-NoProfile\s+-File\s+"([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if($mExec.Success){ $errPath = $mExec.Groups[1].Value; break }
    }
  }

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
  $ptr = [pscustomobject]@{
    rid = $rid; status = "ERROR"; head = $head; file = $errPath; line = $errLine;
    files = [pscustomobject]@{ error_md = $out; transcript = $txPath; error_txt = $errTxtPath }
  }
  $json = ($ptr | ConvertTo-Json -Depth 6)
  Write-LF (Join-Path $LiveDir 'latest-pointer.json') @($json)
}
catch { Write-Warning ("publisher exception: " + $_.Exception.Message) }
finally { exit 0 }