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

# 1) Force recompile
$stamp  = (Get-Date).ToString("yyyyMMddHHmmss")
$csPath = Join-Path $patchDir ("ForceCompile_" + $stamp + ".cs")
$csBody = @"
 // auto-generated to trigger Unity recompile
 // timestamp: $stamp
 public static class __ForceCompile_$stamp { public static string Ping => "$stamp"; }
"@
Write-Utf8 $csPath $csBody
Write-Host "[patch] wrote $csPath"

# 2) Handshake files
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

# 4) Baselines
$asm1 = Join-Path $ProjectRoot "Library\ScriptAssemblies\Assembly-CSharp.dll"
$asm2 = Join-Path $ProjectRoot "Library\ScriptAssemblies\Assembly-CSharp-Editor.dll"
$elog = Join-Path $env:LOCALAPPDATA "Unity\Editor\Editor.log"
$base1 = StampUtc $asm1; $base2 = StampUtc $asm2

Start-Sleep -Milliseconds 500

# 5) Wait for: ack (fresh) AND (DLL updated OR fresh log message)
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
    Step "Initial success gates met → entering short stabilization"
    # --- Stabilization: require 1.5s with no further DLL/log writes ---
    $stableStart = [datetime]::UtcNow
    $prevAsm1 = StampUtc $asm1; $prevAsm2 = StampUtc $asm2
    $prevLog  = if(Test-Path $elog){ (Get-Item $elog).LastWriteTimeUtc } else { [datetime]::MinValue }
    while(([datetime]::UtcNow -lt $deadline)){
      Start-Sleep -Milliseconds 200
      $curAsm1 = StampUtc $asm1; $curAsm2 = StampUtc $asm2
      $curLog  = if(Test-Path $elog){ (Get-Item $elog).LastWriteTimeUtc } else { [datetime]::MinValue }
      if($curAsm1 -eq $prevAsm1 -and $curAsm2 -eq $prevAsm2 -and $curLog -eq $prevLog){
        if(([datetime]::UtcNow - $stableStart).TotalMilliseconds -ge 1500){
          Step "Stable for 1.5s — OK"
          Write-Host "[validate] compile detected — OK"
          try{
            $cleanup = Join-Path (Join-Path $ProjectRoot 'tools\ops') 'cleanup-live.ps1'
            if(Test-Path $cleanup){ & pwsh -NoProfile -ExecutionPolicy Bypass -File $cleanup -RepoRoot "$ProjectRoot" -RetentionDays 7 | Out-Null }
          }catch{}
          exit 0
        }
      } else {
        $prevAsm1 = $curAsm1; $prevAsm2 = $curAsm2; $prevLog = $curLog; $stableStart = [datetime]::UtcNow
      }
    }
  }

  Start-Sleep -Milliseconds 250
}

Write-Error "[validate] TIMEOUT waiting for Unity compile (ack=$ackOk, dll=$dllOk, log=$logOk)"
exit 2