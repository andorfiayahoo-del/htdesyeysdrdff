param(
  [string]$Downloads   = "$env:USERPROFILE\Downloads",
  [string]$LogPath     = "$env:USERPROFILE\patch-router.log",
  [string]$ArchiveRoot = "C:\Users\ander\Patches\Applied",
  [string]$ArchLog     = "$env:USERPROFILE\patch-archiver.log"
)

# Ensure arch log exists
New-Item -ItemType File -Path $ArchLog -Force | Out-Null

# Wait for the router log to exist
while (-not (Test-Path -LiteralPath $LogPath)) { Start-Sleep -Milliseconds 200 }

# Regex: APPLY success: patch_1234.patch OR APPLY success (reconciled): patch_1234.patch
$rx = [regex]'APPLY success(?: \((?:reconciled)\))?:\s*(?<name>patch_\d+\.patch)\b'

# Tail the router log and react on success lines
Get-Content -LiteralPath $LogPath -Wait -Tail 0 -ReadCount 1 | ForEach-Object {
  $line = $_
  $m = $rx.Match($line)
  if (-not $m.Success) { return }

  $name = $m.Groups['name'].Value
  $src  = Join-Path $Downloads $name
  $dstDir = $ArchiveRoot
  if (-not (Test-Path -LiteralPath $dstDir)) {
    try { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null } catch {}
  }

  # Retry a few times in case another process still touches the file for a moment
  $moved = $false
  for ($i=1; $i -le 10 -and -not $moved; $i++) {
    if (Test-Path -LiteralPath $src) {
      try {
        $dst = Join-Path $dstDir $name
        if (Test-Path -LiteralPath $dst) {
          $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
          $dst = Join-Path $dstDir ("{0}-{1}" -f $ts, $name)
        }
        Move-Item -LiteralPath $src -Destination $dst -Force
        Add-Content -LiteralPath $ArchLog -Value ("[{0}] MOVED '{1}' -> '{2}'" -f ((Get-Date).ToString('o')), $src, $dst)
        $moved = $true
      } catch {
        Add-Content -LiteralPath $ArchLog -Value ("[{0}] RETRY {1}/10 for '{2}': {3}" -f ((Get-Date).ToString('o')), $i, $src, $_.Exception.Message)
        Start-Sleep -Milliseconds 250
      }
    } else {
      Start-Sleep -Milliseconds 150
    }
  }

  if (-not $moved) {
    Add-Content -LiteralPath $ArchLog -Value ("[{0}] FAIL move '{1}' (not found or locked)" -f ((Get-Date).ToString('o')), $src)
  }
}
