# run-error-matrix.ps1
$ErrorActionPreference = "Stop"
$RepoRoot = "C:\Users\ander\My project"
$ToolsDir = Join-Path $RepoRoot "tools\ops"
$TestsDir = Join-Path $ToolsDir "tests"
$LiveDir  = Join-Path $RepoRoot "ops\live"
$Wrapper  = Join-Path $ToolsDir "safepush-run.ps1"
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function W([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
$tests = @(
  "bad-parse.ps1",
  "throw-runtime.ps1",
  "native-fail.ps1",
  "exit1.ps1",
  "missing-command.ps1",
  "pipeline-divzero.ps1",
  "nonterm-error.ps1"
)
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add("| Test | RID | Status | File:Line | Commit |")
$rows.Add("|---|---|---|---|---|")
foreach($t in $tests){
  $path = Join-Path $TestsDir $t
  if(!(Test-Path $path)){ continue }
  $cmd = "pwsh -NoProfile -File `"$path`""
  Step ("Running " + $t)
  pwsh -NoProfile -File $Wrapper -RepoRoot "$RepoRoot" -Cmd $cmd | Out-Null
  Start-Sleep -Milliseconds 300
  $ptrPath = Join-Path $LiveDir "latest-pointer.json"
  $rid=""; $status=""; $file=""; $line=""; $head=""
  try {
    if(Test-Path $ptrPath){
      $ptr = Get-Content $ptrPath -Raw | ConvertFrom-Json
      $rid   = "" + $ptr.rid
      $status= "" + $ptr.status
      $file  = "" + $ptr.file
      $line  = "" + $ptr.line
      $head  = "" + $ptr.head
      # snapshot pointer for this test too (optional):
      $dest = Join-Path $LiveDir ("pointer_" + ($t -replace "[^a-zA-Z0-9\-\.]","_") + "_" + $rid + ".json")
      W $dest @((ConvertTo-Json $ptr -Depth 8))
    }
  } catch { }
  $rows.Add("| " + $t + " | " + $rid + " | " + $status + " | " + ($file + ":" + $line) + " | " + $head + " |")
}
$out = @("# Error Matrix", "", (Get-Date).ToString("u"), "", $rows) 
$mdPath = Join-Path $LiveDir "error-matrix.md"
W $mdPath $out
git -C "$RepoRoot" add -- $mdPath "$LiveDir\pointer_*.json" | Out-Null
git -C "$RepoRoot" commit -m "ops: add error-matrix run (auto)" | Out-Null
$hasVpush = (git -C "$RepoRoot" config --get alias.vpush) -ne $null
if($hasVpush){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }