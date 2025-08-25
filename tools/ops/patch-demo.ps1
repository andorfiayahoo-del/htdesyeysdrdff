param([string]$ProjectRoot = (Get-Location).Path, [int]$TimeoutSec = 900)
$ErrorActionPreference = "Stop"

function Write-Utf8CrLf {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string[]]$Lines)
  $txt = ($Lines -join "`r`n")
  $enc = [Text.UTF8Encoding]::new($false)
  $dir = Split-Path -LiteralPath $Path
  if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  [IO.File]::WriteAllText($Path,$txt,$enc)
}

$stamp     = Get-Date -Format "yyyyMMddHHmmss"
$uniq      = [guid]::NewGuid().ToString()
$ns        = "Ops.PatchTest"
$className = "CompileKick_$stamp"
$testDir   = Join-Path $ProjectRoot "Assets\Ops\PatchTest"
$csFile    = Join-Path $testDir  "$className.cs"
[IO.Directory]::CreateDirectory($testDir) | Out-Null

$log = '      Debug.Log("[OpsTest] " + System.DateTime.UtcNow.ToString("o") + " __UNIQ__");'

$CS = @()
$CS += "using UnityEngine;"
$CS += ""
$CS += "namespace $ns {"
$CS += "  public sealed class $className : MonoBehaviour {"
$CS += "    void Awake() {"
$CS += ($log.Replace("__UNIQ__", $uniq))
$CS += "    }"
$CS += "  }"
$CS += "}"

Write-Utf8CrLf -Path $csFile -Lines $CS
Write-Host "[Step 1] Applied test patch: $csFile" -ForegroundColor Cyan

$stepWait = Join-Path $PSScriptRoot "step-wait-unity.ps1"
if (-not (Test-Path -LiteralPath $stepWait)) { throw "Missing waiter: $stepWait" }
Write-Host "[Step 2] Focus Unity, then wait for compile (no keypress)" -ForegroundColor Cyan
& $stepWait -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec

$reportPath = Join-Path $ProjectRoot "ops\live\match.json"
[IO.Directory]::CreateDirectory((Split-Path -LiteralPath $reportPath)) | Out-Null
$obj = [ordered]@{ matched=@("Assets/Ops/PatchTest/$className.cs"); mismatched=@(); missing=@() }
[IO.File]::WriteAllText($reportPath, ($obj | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))

$stepVal = Join-Path $PSScriptRoot "step-validate-match.ps1"
if (-not (Test-Path -LiteralPath $stepVal)) { throw "Missing validator: $stepVal" }
Write-Host "[Step 3] Validate match/mismatch" -ForegroundColor Cyan
& $stepVal -ProjectRoot $ProjectRoot

git -C $ProjectRoot add -- "Assets/Ops/PatchTest/$className.cs" "ops/live/match.json"
git -C $ProjectRoot vpush
