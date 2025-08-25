# tools/ops/publish-latest-error.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [string]$LiveDir  = (Join-Path $RepoRoot 'ops\live')
)
$ErrorActionPreference = 'Continue'
trap { Write-Warning ("publisher: " + $_.Exception.Message); continue }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
try {
  if(!(Test-Path $LiveDir)){ New-Item -ItemType Directory -Path $LiveDir | Out-Null }
  $errFiles = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
  $txFiles  = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending
  $rid = 'unknown'; $errTxt = @(); $txTail = @(); $txPath = ''; $errTxtPath = ''
  if($errFiles){ $err = $errFiles[0]; $rid = ($err.BaseName -replace '^error_',''); $errTxt = Get-Content $err.FullName -ErrorAction SilentlyContinue; $errTxtPath = $err.FullName }
  if($txFiles){ $tx = $txFiles[0]; if($rid -eq 'unknown'){ $rid = ($tx.BaseName -replace '^transcript_','') } ; $txTail = Get-Content $tx.FullName -Tail 120 -ErrorAction SilentlyContinue; $txPath = $tx.FullName }

  # Robust File/Line extraction
  $fullErr = ($errTxt -join "`n")
  $errPath = ''; $errLine = ''
  # 1) ParserError: <path>:<line>
  $m = [regex]::Match($fullErr, 'ParserError:\s+(.+?):(\d+)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if($m.Success){ $errPath = $m.Groups[1].Value; $errLine = $m.Groups[2].Value }
  # 2) General runtime:  At C:\path\file.ps1:<line> char:
  if(-not $m.Success){
    $m2 = [regex]::Match($fullErr, '(?m)^\s*At\s+(.+?):(\d+)\s+char:', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m2.Success){ $errPath = $m2.Groups[1].Value; $errLine = $m2.Groups[2].Value }
  }
  # 3) Table form:  Line |  36 | ... (fallback gets line only)
  if([string]::IsNullOrWhiteSpace($errLine)){
    $m3 = [regex]::Match($fullErr, '(?m)^\s*Line\s*\|\s*(\d+)\s*\|', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if($m3.Success){ $errLine = $m3.Groups[1].Value }
  }
  # If file unknown, infer from transcript 'EXEC: pwsh -File "<path>"'
  if([string]::IsNullOrWhiteSpace($errPath) -and $txTail){
    foreach($tl in $txTail){
      $mExec = [regex]::Match($tl, 'EXEC:\s+pwsh\s+-NoProfile\s+-File\s+"([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
      if($mExec.Success){ $errPath = $mExec.Groups[1].Value; break }
    }
  }

  # Markdown snapshot
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

  # Pointer JSON (for the assistant to find stuff fast)
  $head = '' ; try { $head = (git -C "$RepoRoot" rev-parse HEAD).Trim() } catch { }
  $ptr = [pscustomobject]@{ rid = $rid; status = "ERROR"; head = $head; file = $errPath; line = $errLine; files = [pscustomobject]@{ error_md = $out; transcript = $txPath; error_txt = $errTxtPath } }
  $json = ($ptr | ConvertTo-Json -Depth 6)
  Write-LF (Join-Path $LiveDir 'latest-pointer.json') @($json)
} catch {
  Write-Warning ("publisher exception: " + $_.Exception.Message)
} finally {
  exit 0
}