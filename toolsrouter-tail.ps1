param(
  [string]$LogPath = "$env:USERPROFILE\patch-router.log"
)

function Write-ColoredLine([string]$line) {
  $fg = 'Gray'
  switch -Regex ($line) {

    # ✅ Success
    'APPLY success\b'                        { $fg = 'Green'; break }
    'APPLY success .*local-only'             { $fg = 'Green'; break }
    'APPLY success .*reconciled'             { $fg = 'Green'; break }
    'UNITY compiled\b'                       { $fg = 'Green'; break }
    'LINT ok\b'                              { $fg = 'Green'; break }
    'FIXUP (wrote|appended)'                 { $fg = 'Green'; break }
    'POSTCHECK .*#if=\d+ #endif=\d+'         { $fg = 'Green'; break }

    # ⚠️ Waits / warnings
    'UNITY wait\b'                           { $fg = 'Yellow'; break }
    'VERIFY WARN\b'                          { $fg = 'Yellow'; break }
    'APPLY .*pull-warning'                   { $fg = 'Yellow'; break }
    'APPLY .*push-warning'                   { $fg = 'Yellow'; break }
    'RECONCILE result: .*identical'          { $fg = 'Yellow'; break }

    # ❌ Failures / errors
    'APPLY (failed|check-failed|verify-failed|pull-failed|push-failed)\b' { $fg = 'Red'; break }
    'RECONCILE .*failed'                    { $fg = 'Red'; break }
    'LINT fail\b'                           { $fg = 'Red'; break }
    '\bERROR\b'                              { $fg = 'Red'; break }
    '\bABORT\b'                              { $fg = 'Red'; break }
    'APPLY exception\b'                      { $fg = 'Red'; break }
    # Only mark as red if git actually says error/fatal
    '^GIT (note: )?.*?(error:|fatal:)'       { $fg = 'Red'; break }

    # ℹ️ Neutral/ops
    'APPLY start\b'                          { $fg = 'Cyan'; break }
    'READY detected\b'                       { $fg = 'Cyan'; break }
    'WATCH polling\b'                        { $fg = 'Cyan'; break }
    'BOOT '                                  { $fg = 'Cyan'; break }
    'SCRIPT version='                        { $fg = 'Cyan'; break }
    'ENSURE main'                            { $fg = 'Cyan'; break }
    'RECONCILE (wrote|replaced)'             { $fg = 'Cyan'; break }
    'UNITY skip\b'                           { $fg = 'Cyan'; break }

    # Git chatter — make harmless stuff yellow or dim
    '^GIT (note: )?From '                    { $fg = 'Yellow'; break }
    '^GIT (note: )?To '                      { $fg = 'Yellow'; break }
    '^GIT \[.*\]'                            { $fg = 'DarkGray'; break }
    '^GIT branch '                           { $fg = 'DarkGray'; break }

    default { $fg = 'Gray' }
  }
  Write-Host $line -ForegroundColor $fg
}

# Wait for the log file, then color-tail it
if (-not (Test-Path -LiteralPath $LogPath)) {
  Write-Host "Waiting for $LogPath..." -ForegroundColor Yellow
  while (-not (Test-Path -LiteralPath $LogPath)) { Start-Sleep -Milliseconds 250 }
}
Get-Content -LiteralPath $LogPath -Wait -Tail 60 | ForEach-Object { Write-ColoredLine $_ }

