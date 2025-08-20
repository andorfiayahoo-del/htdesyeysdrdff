# ---- Move helper ----
function Move-AppliedPatch([string]$fullPath,[string]$name) {
  try {
    $appliedDir = Join-Path $Downloads 'AppliedPatches'
    if (-not (Test-Path -LiteralPath $appliedDir)) { New-Item -ItemType Directory -Path $appliedDir -Force | Out-Null }
    if (Test-Path -LiteralPath $fullPath) {
      $leaf = Split-Path -Leaf $fullPath
      $dest = Join-Path $appliedDir $leaf
      if (Test-Path -LiteralPath $dest) {
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dest = Join-Path $appliedDir ("{0}-{1}" -f $ts, $leaf)
      }
      Move-Item -LiteralPath $fullPath -Destination $dest -Force
      Write-Log ("APPLY archive: moved '{0}' to '{1}'" -f $leaf,$dest) 'Y'
    }
  } catch {
    Write-Log ("APPLY archive-failed for {0}: {1}" -f $name,$_.Exception.Message) 'R'
  }
}
