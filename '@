param()
$OutFile = Join-Path $PSScriptRoot "here-string-demo.txt"
$stamp   = Get-Date -Format "o"
$content = @'
# Demo using PowerShell here-strings
This file proves the closing '@ is present.
"Stamp: $stamp" (shown literally if treated as text in a single-quoted here-string)
'@
Set-Content -LiteralPath $OutFile -Value $content -Encoding utf8
Write-Host "Wrote $OutFile"
