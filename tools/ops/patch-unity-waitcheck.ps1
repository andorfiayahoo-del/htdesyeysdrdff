# tools/ops/patch-unity-waitcheck.ps1
param(
  [string]$ProjectRoot = 'C:\Users\ander\My project',
  [int]$TimeoutSec = 300,
  [switch]$IntroduceError
)
$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Warning $m }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
function Get-AsmStamp([string]$Root){
  $sa = Join-Path $Root 'Library\ScriptAssemblies'
  if(!(Test-Path $sa)){ return [datetime]::MinValue }
  $files = Get-ChildItem $sa -Filter *.dll -ErrorAction SilentlyContinue
  if(-not $files){ return [datetime]::MinValue }
  return ($files | Sort-Object LastWriteTimeUtc | Select-Object -Last 1).LastWriteTimeUtc
}

if(!(Test-Path $ProjectRoot)){ throw "Project root not found: $ProjectRoot" }
$assetsDir = Join-Path $ProjectRoot 'Assets\Ops\WaitCheck'
if(!(Test-Path $assetsDir)){ New-Item -ItemType Directory -Path $assetsDir | Out-Null }
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$className = "OpsWaitCheck_" + $ts
$csPath = Join-Path $assetsDir ("WaitCheck_" + $ts + ".cs")

# Compose a tiny MonoBehaviour; optionally inject a C# syntax error to force failure
$CS = New-Object System.Collections.Generic.List[string]
$CS.Add("using UnityEngine;")
$CS.Add("public class " + $className + " : MonoBehaviour {")
$CS.Add("  void Start(){ Debug.Log(\\"[waitcheck] "+$className+" Start\\"); }")
$CS.Add("  void Update(){}")
$CS.Add("}")
if($IntroduceError){ $CS.Add("int oops = ;") }  # <- deliberate compiler error line
Step ("Writing " + $csPath)
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($csPath, ($CS -join "`r`n"), $enc)

$baseline = Get-AsmStamp $ProjectRoot
Step "Focus Unity, then wait for compile (watching ScriptAssemblies timestamp)"
Write-Host " — bring the Unity Editor window to the front; I will wait up to $TimeoutSec seconds."
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$compiledAt = $null
do {
  Start-Sleep -Milliseconds 400
  $now = Get-AsmStamp $ProjectRoot
  if($now -gt $baseline){ $compiledAt = $now; break }
} while((Get-Date) -lt $deadline)

if(-not $compiledAt){
  # Grab a short Editor.log tail to aid diagnostics, then fail (wrapper will push artifacts)
  $elog = Join-Path $env:LOCALAPPDATA "Unity\Editor\Editor.log"
  $tail = @() ; if(Test-Path $elog){ try { $tail = Get-Content $elog -Tail 80 } catch { } }
  $msg = "Unity compile did not finish within ${TimeoutSec}s; check transcript and Editor.log tail."
  if($tail.Count -gt 0){ $msg += "`nEditor.log tail:`n" + ($tail -join "`n") }
  throw $msg
}

# Success: write a tiny summary and push so the assistant can confirm from the repo
$delta = [Math]::Round((New-TimeSpan -Start $baseline -End $compiledAt).TotalSeconds, 2)
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# Unity WaitCheck")
$summary.Add("")
$summary.Add("**Result:** OK  ")
$summary.Add("**Class:** $className  ")
$summary.Add("**Source:** $csPath  ")
$summary.Add("**Baseline ScriptAssemblies mtime (UTC):** " + $baseline.ToString("o") + "  ")
$summary.Add("**Compiled mtime (UTC):** " + $compiledAt.ToString("o") + "  ")
$summary.Add("**Delta (s):** $delta  ")
$summary.Add("")
$outMD = Join-Path (Join-Path $ProjectRoot "ops\live") "unity-waitcheck.md"
Write-LF $outMD $summary.ToArray()
try {
  git -C "$ProjectRoot" add -- $outMD | Out-Null
  git -C "$ProjectRoot" commit -m ("ops: unity waitcheck OK (" + $className + ") Δ=" + $delta + "s") | Out-Null
  $hasVpush = (git -C "$ProjectRoot" config --get alias.vpush) -ne $null
  if($hasVpush){ git -C "$ProjectRoot" vpush | Out-Null } else { git -C "$ProjectRoot" push -u origin main | Out-Null }
} catch { Warn ("could not push summary: " + $_.Exception.Message) }
Write-Host "[done] Unity compile observed in $delta s" -ForegroundColor Green