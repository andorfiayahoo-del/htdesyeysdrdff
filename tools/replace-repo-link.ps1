$ErrorActionPreference = 'Stop'
$Old = 'https://github.com/andorfiayahoo-del/htdesyeysdrdff'
$New = 'https://github.com/andorfiayahoo-del/htdesyeysdrdff'
Write-Host ('Replacing repo URL: ' + $Old + '  -->  ' + $New) -ForegroundColor Yellow
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
$root = (git rev-parse --show-toplevel).Trim()
Set-Location $root

# Exclude typical binaries and vendor dirs; only text-like files
$exclude = @('^.git/', '^Library/', '^Temp/', '^Obj/', '^Build(s)?/', '^Logs/', '^Packages/', '^UserSettings/')
$files = git ls-files
$targets = @()
foreach ($f in $files) {
  $skip = $false
  foreach ($rx in $exclude) { if ($f -match $rx) { $skip = $true; break } }
  if ($skip) { continue }
  $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
  if ($ext -in @('.png','.jpg','.jpeg','.gif','.bmp','.ico','.dll','.exe','.pdf','.docx','.zip','.7z','.mp3','.mp4','.wav','.ogg','.fbx','.obj')) { continue }
  $text = try { Get-Content -LiteralPath $f -Raw -Encoding UTF8 } catch { '' }
  if ($text -ne '' -and $text.Contains($Old)) {
    $text = $text.Replace($Old, $New)
    Set-Content -LiteralPath $f -Value $text -Encoding UTF8
    $targets += $f
    Write-Host ('  patched: ' + $f) -ForegroundColor Green
  }
}
if ($targets.Count -eq 0) { Write-Host 'No files contained the old URL.' -ForegroundColor Cyan; exit 0 }
git add -A
git commit -m ('chore: replace repo URL ' + $Old + ' -> ' + $New)
git push
Write-Host ('Done. Updated ' + $targets.Count + ' file(s).') -ForegroundColor Green


