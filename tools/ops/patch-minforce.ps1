# tools/ops/patch-minforce.ps1
param(
  [string]$ProjectRoot = "C:\Users\ander\My project",
  [int]$TimeoutSec = 600
)
$ErrorActionPreference = "Stop"

function Step($m){ Write-Host "[Step] $m" -ForegroundColor Cyan }
function Write-Utf8([string]$Path,[string]$Text){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path,$Text,$enc) }
function StampUtc($p){ if(Test-Path $p){ (Get-Item $p).LastWriteTimeUtc } else { [datetime]::MinValue } }

# Ensure dirs
$editorDir = Join-Path $ProjectRoot "Assets\Ops\Editor"
$patchDir  = Join-Path $ProjectRoot "Assets\Ops\PatchTest"
$liveDir   = Join-Path $ProjectRoot "ops\live"
foreach($d in @($editorDir,$patchDir,$liveDir)){ if(!(Test-Path $d)){ New-Item -ItemType Directory -Path $d | Out-Null } }

# Ensure sentinel present (idempotent; content managed outside)
# (The file itself is authored/updated by the outer one-shot.)
if(!(Test-Path (Join-Path $editorDir "OpsCompileSignal.cs"))){
  Write-Warning "OpsCompileSignal.cs not found; Unity will compile it now."
}

# 1) Drop tiny C# to force recompile
$stamp  = (Get-Date).ToString("yyyyMMddHHmmss")
$csPath = Join-Path $patchDir ("ForceCompile_" + $stamp + ".cs")
$csBody = @"
 // auto-generated to trigger Unity recompile
 // timestamp: $stamp
 public static class __ForceCompile_$stamp { public static string Ping => "$stamp"; }
"@
Write-Utf8 $csPath $csBody
Write-Host "[patch] wrote $csPath"

# 2) Prepare handshake files
$token        = (Get-Date).ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([guid]::NewGuid().ToString("N"))
$triggerPath  = Join-Path $liveDir "compile-trigger.txt"
$ackPath      = Join-Path $liveDir ("compile-ack_" + $token + ".txt")
Write-Utf8 $triggerPath $token
if(Test-Path $ackPath){ Remove-Item $ackPath -Force -ErrorAction SilentlyContinue }
$triggerTime  = (Get-Item $triggerPath).LastWriteTimeUtc

# 3) Focus Unity (best-effort)
try{
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
  $unity = Get-Process -Name Unity -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if($unity){ [void][Win32]::SetForegroundWindow($unity.MainWindowHandle); Step "Focused Unity (pid=$($unity.Id))" }
}catch{}

# 4) Baselines and paths
$asm1 = Join-Path $ProjectRoot "Library\ScriptAssemblies\Assembly-CSharp.dll"
$asm2 = Join-Path $ProjectRoot "Library\ScriptAssemblies\Assembly-CSharp-Editor.dll"
$elog = Join-Path $env:LOCALAPPDATA "Unity\Editor\Editor.log"
$base1 = StampUtc $asm1; $base2 = StampUtc $asm2
$elogBase = StampUtc $elog

Start-Sleep -Milliseconds 500

# 5) Wait for: ack (fresh) AND (DLL updated OR fresh log shows compile finished)
$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
$ackOk = $false; $dllOk = $false; $logOk = $false

Step "Waiting for Unity ack (token) AND compile evidence (DLL or Editor.log), timeout=${TimeoutSec}s"
while([datetime]::UtcNow -lt $deadline){
  if(-not $ackOk -and (Test-Path $ackPath)){
    $ackTime = (Get-Item $ackPath).LastWriteTimeUtc
    if($ackTime -ge $triggerTime){ $ackOk = $true; Step "Ack OK (fresh ≥ trigger time)" }
  }

  if(-not $dllOk){
    $n1 = StampUtc $asm1; $n2 = StampUtc $asm2
    if($n1 -gt $base1 -or $n2 -gt $base2){ $dllOk = $true; Step "DLLs updated" }
  }

  if(Test-Path $elog){
    $ei = Get-Item $elog
    if($ei.LastWriteTimeUtc -gt $triggerTime){
      try{
        $tail = Get-Content $elog -Tail 500 -ErrorAction SilentlyContinue
        if($tail | Select-String -SimpleMatch -Pattern "Compilation completed", "Compilation finished", "Refresh: detected"){
          if(-not $logOk){ $logOk = $true; Step "Editor.log indicates compile finished (fresh)" }
        }
      }catch{}
    }
  }

  if($ackOk -and ($dllOk -or $logOk)){
    Write-Host "[validate] compile detected — OK"
    exit 0
  }
  Start-Sleep -Milliseconds 250
}

Write-Error "[validate] TIMEOUT waiting for Unity compile (ack=$ackOk, dll=$dllOk, log=$logOk)"
exit 2