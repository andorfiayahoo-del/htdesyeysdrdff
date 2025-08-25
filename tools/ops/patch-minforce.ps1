# tools/ops/patch-minforce.ps1
param(
  [string]$ProjectRoot = 'C:\Users\ander\My project',
  [int]$TimeoutSec = 600
)
$ErrorActionPreference = 'Stop'

function Step($m){ Write-Host "[Step] $m" -ForegroundColor Cyan }
function Write-Utf8([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path,$Text,$enc)
}

# Ensure directories
$editorDir = Join-Path $ProjectRoot 'Assets\Ops\Editor'
$patchDir  = Join-Path $ProjectRoot 'Assets\Ops\PatchTest'
$liveDir   = Join-Path $ProjectRoot 'ops\live'
foreach($d in @($editorDir,$patchDir,$liveDir)){ if(!(Test-Path $d)){ New-Item -ItemType Directory -Path $d | Out-Null } }

# 0) Install (idempotent) Editor sentinel that acks after scripts reload
$editorPath = Join-Path $editorDir 'OpsCompileSignal.cs'
$editorSrc = @"
using UnityEditor;
using UnityEngine;
using System.IO;
using System;

[InitializeOnLoad]
public static class OpsCompileSignal {
    static OpsCompileSignal() {
        try {
            var projectRoot = Directory.GetParent(Application.dataPath).FullName;
            var liveDir = Path.Combine(projectRoot, "ops", "live");
            var trigger = Path.Combine(liveDir, "compile-trigger.txt");
            if (File.Exists(trigger)) {
                var token = File.ReadAllText(trigger).Trim();
                if (!string.IsNullOrEmpty(token)) {
                    var ack = Path.Combine(liveDir, "compile-ack_" + token + ".txt");
                    File.WriteAllText(ack, DateTime.UtcNow.ToString("o"));
                    Debug.Log("[OpsCompileSignal] ack " + token);
                }
            }
        } catch (Exception ex) {
            Debug.LogWarning("[OpsCompileSignal] exception: " + ex.Message);
        }
    }
}
"@
Write-Utf8 $editorPath $editorSrc

# 1) Drop a tiny C# to guarantee a recompile
$stamp = (Get-Date).ToString("yyyyMMddHHmmss")
$csPath = Join-Path $patchDir ("ForceCompile_" + $stamp + ".cs")
$csBody = @"
 // auto-generated to trigger Unity recompile
 // timestamp: $stamp
 public static class __ForceCompile_$stamp { public static string Ping => "$stamp"; }
"@
Write-Utf8 $csPath $csBody
Write-Host "[patch] wrote $csPath"
Write-Host "[patch] ensured sentinel: $editorPath"

# 2) Create unique token & trigger file that the Editor sentinel will ack
$token = (Get-Date).ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([guid]::NewGuid().ToString("N"))
$triggerPath = Join-Path $liveDir 'compile-trigger.txt'
Write-Utf8 $triggerPath $token
$ackPath = Join-Path $liveDir ("compile-ack_" + $token + ".txt")
if(Test-Path $ackPath){ Remove-Item $ackPath -Force -ErrorAction SilentlyContinue }

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

# 4) Prepare fallback assembly timestamp detectors
function StampUtc($p){ if(Test-Path $p){ (Get-Item $p).LastWriteTimeUtc } else { [datetime]::MinValue } }
$asm1 = Join-Path $ProjectRoot 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$asm2 = Join-Path $ProjectRoot 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$base1 = StampUtc $asm1; $base2 = StampUtc $asm2

# tiny settle to let Unity pick up new files
Start-Sleep -Milliseconds 500

# 5) Wait for ack OR assembly updates
$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
$ok = $false
Step "Waiting for Unity ack token or DLL updates (timeout=${TimeoutSec}s)"
while([datetime]::UtcNow -lt $deadline){
  if(Test-Path $ackPath){
    $ok = $true; Step "Ack file detected for token $token"; break
  }
  $n1 = StampUtc $asm1; $n2 = StampUtc $asm2
  if($n1 -gt $base1 -or $n2 -gt $base2){
    $ok = $true; Step "Assemblies updated"; break
  }
  Start-Sleep -Milliseconds 250
}

if($ok){
  Write-Host "[validate] compile detected — OK"
  exit 0
}else{
  Write-Error "[validate] TIMEOUT waiting for Unity compile (no ack; no DLL updates)"
  exit 2
}