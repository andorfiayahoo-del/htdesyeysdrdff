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

# 1) Drop a tiny C# to guarantee a recompile
$stamp = (Get-Date).ToString("yyyyMMddHHmmss")
$patchDir = Join-Path $ProjectRoot 'Assets\Ops\PatchTest'
if(!(Test-Path $patchDir)){ New-Item -ItemType Directory -Path $patchDir | Out-Null }
$csPath = Join-Path $patchDir ("ForceCompile_" + $stamp + ".cs")
$csBody = @"
 // auto-generated to trigger Unity recompile
 // timestamp: $stamp
 public static class __ForceCompile_$stamp { public static string Ping => "$stamp"; }
"@
Write-Utf8 $csPath $csBody
Write-Host "[patch] wrote $csPath"

# 2) Try to focus Unity (best-effort, non-fatal)
try {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
  $unity = Get-Process -Name Unity -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if($unity){ [void][Win32]::SetForegroundWindow($unity.MainWindowHandle); Step "Focused Unity (pid=$($unity.Id))" }
} catch { }

# 3) Prepare success detectors (use UTC and only trust fresh Editor.log writes)
$startUtc = [datetime]::UtcNow
$asm1 = Join-Path $ProjectRoot 'Library\ScriptAssemblies\Assembly-CSharp.dll'
$asm2 = Join-Path $ProjectRoot 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
$elog = Join-Path $env:LOCALAPPDATA 'Unity\Editor\Editor.log'

function StampUtc($p){ if(Test-Path $p){ (Get-Item $p).LastWriteTimeUtc } else { [datetime]::MinValue } }
$base1 = StampUtc $asm1; $base2 = StampUtc $asm2
$elogBaseTime = if (Test-Path $elog) { (Get-Item $elog).LastWriteTimeUtc } else { [datetime]::MinValue }

# give Unity a moment to notice the new file
Start-Sleep -Milliseconds 500

Step "Waiting for compile (assemblies or fresh Editor.log), timeout=${TimeoutSec}s"
$ok = $false
$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
while([datetime]::UtcNow -lt $deadline){
  # DLL timestamp signal
  $n1 = StampUtc $asm1; $n2 = StampUtc $asm2
  if($n1 -gt $base1 -or $n2 -gt $base2){
    $ok = $true; Step "Assemblies updated"; break
  }

  # Editor.log signal (only if fresh writes happened after start)
  if(Test-Path $elog){
    try{
      $elogInfo = Get-Item $elog
      if ($elogInfo.LastWriteTimeUtc -gt $startUtc) {
        $tail = Get-Content $elog -Tail 500 -ErrorAction SilentlyContinue
        if ($tail | Select-String -SimpleMatch -Pattern "Script compilation", "Compilation completed", "Compilation finished", "Refresh: detected"){
          $ok = $true; Step "Editor.log indicates compile finished (fresh)"; break
        }
      }
    } catch { }
  }

  Start-Sleep -Milliseconds 250
}

if($ok){
  Write-Host "[validate] compile detected — OK"
  exit 0
} else {
  Write-Error "[validate] TIMEOUT waiting for Unity compile"
  exit 2
}