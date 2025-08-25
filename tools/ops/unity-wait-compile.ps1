param(
  [string]$ProjectRoot = (Get-Location).Path,
  [int]$TimeoutSec = 300,
  [string]$UnityExe,
  [switch]$EmitPing
)

$Sentinel = Join-Path $ProjectRoot "ops\live\unity-compile.json"
[IO.Directory]::CreateDirectory((Split-Path -LiteralPath $Sentinel)) | Out-Null

if ($EmitPing -and $UnityExe) {
  & $UnityExe -batchmode -nographics -projectPath $ProjectRoot -quit -executeMethod Ops.CompileSentinel.EmitStatusCLI | Out-Host
}

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ($true) {
  if (Test-Path -LiteralPath $Sentinel) {
    try {
      $raw = Get-Content -LiteralPath $Sentinel -Raw -ErrorAction Stop
      $st = $raw | ConvertFrom-Json
      if (-not $st.isCompiling -and -not $st.isUpdating) {
        Write-Host "[unity-wait-compile] OK: state=$($st.state) compiling=$($st.isCompiling) updating=$($st.isUpdating) at $($st.utc)"
        break
      } else {
        Write-Host "[unity-wait-compile] Waiting: state=$($st.state) compiling=$($st.isCompiling) updating=$($st.isUpdating)..."
      }
    } catch {
      Write-Host "[unity-wait-compile] Sentinel unreadable (race), retrying..."
    }
  } else {
    Write-Host "[unity-wait-compile] Sentinel not found yet, retrying..."
  }
  if (Get-Date -gt $deadline) { throw "Timeout waiting for Unity compile. Sentinel=$Sentinel" }
  Start-Sleep -Milliseconds 300
}