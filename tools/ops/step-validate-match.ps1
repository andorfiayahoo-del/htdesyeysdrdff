param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$ReportPath,
  [switch]$Soft
)
$ErrorActionPreference = "Stop"
if (-not $ReportPath) {
  $candidates = @(
    Join-Path $ProjectRoot "ops\live\match.json",
    Join-Path $ProjectRoot "ops\live\match-mismatch.json",
    Join-Path $ProjectRoot "ops\live\patch-verify.json"
  )
  $ReportPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $ReportPath) {
  $msg = "[validate-match] No report found in ops\live\. Skipping."
  if ($Soft) { Write-Host $msg -ForegroundColor Yellow; exit 0 }
  Write-Host $msg -ForegroundColor Yellow; exit 0
}
$raw = Get-Content -LiteralPath $ReportPath -Raw
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
if ($j -ne $null) {
  $matched    = @($j.matched).Count
  $mismatched = @($j.mismatched).Count
  $missing    = @($j.missing).Count
  Write-Host "[validate-match] matched=$matched mismatched=$mismatched missing=$missing" -ForegroundColor Cyan
  if (-not $Soft -and (($mismatched -gt 0) -or ($missing -gt 0))) { throw "Match validation failed." }
} else {
  Write-Host "[validate-match] Non-JSON report, showing last lines:" -ForegroundColor Cyan
  $raw -split "`n" | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }
}
