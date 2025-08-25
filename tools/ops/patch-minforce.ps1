param([string]$ProjectRoot = (Get-Location).Path, [int]$TimeoutSec = 900)
$ErrorActionPreference = "Stop"
function Write-Utf8CrLf {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
  $d = Split-Path -LiteralPath $Path; if ($d) { [IO.Directory]::CreateDirectory($d) | Out-Null }
  $Text = $Text -replace "`r`n","`n"; $Text = $Text -replace "`r","`n"; $Text = $Text -replace "`n","`r`n"
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$className = "ForceCompile_" + $stamp
$csDir  = Join-Path $ProjectRoot "Assets\Ops\PatchTest"
$csFile = Join-Path $csDir ($className + ".cs")
$lines = @(
  "using UnityEngine;",
  "",
  "namespace Ops.PatchTest {",
  "  public sealed class " + $className + " : MonoBehaviour {",
  "    void Awake() { Debug.Log(""[ForceCompile] injected script loaded""); }",
  "  }",
  "}"
)
Write-Utf8CrLf -Path $csFile -Text (($lines -join "`n"))
Write-Host "[patch] wrote $csFile" -ForegroundColor Cyan

$stepWait = Join-Path $PSScriptRoot "step-wait-unity.ps1"
if (-not (Test-Path -LiteralPath $stepWait)) { throw "Missing step: $stepWait" }
Write-Host "[Step] Focus Unity, then wait (RequireBusy)" -ForegroundColor Cyan
& $stepWait -ProjectRoot $ProjectRoot -TimeoutSec $TimeoutSec -RequireBusy

# Produce a tiny dummy match report so the validator runs a full pass
$liveDir = Join-Path $ProjectRoot "ops\live"
[IO.Directory]::CreateDirectory($liveDir) | Out-Null
$report = Join-Path $liveDir "match.json"
$json = "{""matched"":[""" + $className + """],""mismatched"":[],""missing"":[]}"
[IO.File]::WriteAllText($report,$json,[Text.UTF8Encoding]::new($false))

$val = Join-Path $PSScriptRoot "step-validate-match.ps1"
& $val -ProjectRoot $ProjectRoot -ReportPath $report

$rel = "Assets/Ops/PatchTest/" + $className + ".cs"
$metaRel = $rel + ".meta"
git -C $ProjectRoot add -- $rel 2>$null
if (Test-Path -LiteralPath (Join-Path $ProjectRoot $metaRel)) { git -C $ProjectRoot add -- $metaRel 2>$null }
git -C $ProjectRoot vpush