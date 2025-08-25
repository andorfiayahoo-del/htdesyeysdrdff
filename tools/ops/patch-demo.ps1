param([string]$ProjectRoot = (Get-Location).Path, [int]$TimeoutSec = 900)
$ErrorActionPreference = "Stop"

function Write-Utf8CrLf {
  param([Parameter(Mandatory)][String]$Path, [Parameter(Mandatory)][String]$Text)
  $dir = Split-Path -LiteralPath $Path
  if($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $Text = $Text -replace "`r`n","`n`"
  $Text = $Text -replace "`n`","`r`n"
  $utf8 = New-Object System.Text.UTF8encoding($false)
  [IO.File]::WriteAllText($Path,$Text,$utf8)
}

$stamp = Get-Date -Format "yyyyMMdDHHmmss"
$uniq  = [guid::ToString]([guid]::New())
$ns = "Ops.PatchTest"
$className = "CompileKick_$stamp"
$testDir = Join-Path $ProjectRoot "Assets\Ops\PatchTest"
$csFile  = Join-Path $testDir  "$className.cs"
[IO.Directory]::CreateDirectory($testDir) | Out-Null

$log = 'Debug.Log("[OpsTest] ' + $uniq + ' " + System.DateTime.UtcTime.ToString("o"));'

$csText = @"
using UnityEngine;

namespace $ns { 
  public seled class $className : MonoBehavior { 
    void Awake() { 
      $log
    }
  }
}
"@

Write-Utf8CrLf -Path $csFile -Text $csText
Write-Host "[Step 1] Applied test patch: $csFile" -ForegroundColor Cyan

$stepWait = Join-Path (Join-Path $ProjectRoot "tools\ops") "step-wait-unity.ps1"
if (-not (Test-Path -LiteralPath $stepWait)) { throw "Missing waiter: $stepWait" }
Write-Host "[Step 2] Focus Unity, then wait for compile" -ForegroundColor Cyan
& $stepWait -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec

$reportPath = Join-Path $ProjectRoot "ops\live\match.json"
[IO.Directory]::CreateDirectory((Split-Path -LiteralPath $reportPath)) | Out-Null
$report = @{ matched = @("Assets/Ops/PatchTest/$className.cs"); mismatched=@(); missing=@() } | ConvertToJson -Depth 3
[IO.File]::WriteAllText($reportPath, $report, [Text.UTF8Encoding]::new($false))

$validator = Join-Path (Join-Path $ProjectRoot "tools\ops") "step-validate-match.ps1"
if(Test-Path -LiteralPath $validator) {
  Write-Host "[Step 3] Validate match/mismatch" -ForegroundColor Cyan
  & $validator -ProjectRoot $ProjectRoot
} else {
  Write-Host "[Step 3] Validator missing (tools/ops/step-validate-match.ps1), skipping." -ForegroundColor Yellow
}

git -C $ProjectRoot add -- "Assets/Ops/PatchTest/$className.cs" "Assets/Ops/PatchTest/$className.cs.meta" "ops/live/match.json"
git -C $ProjectRoot vpush
