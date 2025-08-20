$ErrorActionPreference = 'Stop'
$Old = 'https://github.com/andorfiayahoo-del/htdesyeysdrdff'
$New = 'https://github.com/andorfiayahoo-del/htdesyeysdrdff'
Write-Host ('Replacing repo URL: ' + $Old + '  -->  ' + $New) -ForegroundColor Yellow
$root = (git rev-parse --show-toplevel).Trim()
Set-Location $root

$exclude = @('^.git/','^Library/','^Temp/','^Obj/','^Build(s)?/','^Logs/','^Packages/','^UserSettings/','.github/')
$binExt = @('.png','.jpg','.jpeg','.gif','.bmp','.ico','.dll','.exe','.pdf','.docx','.zip','.7z','.mp3','.mp4','.wav','.ogg','.fbx','.obj','.unitypackage')
$changed = @()
$files = git ls-files
foreach ($f in $files) {
  $skip = $false
  foreach ($rx in $exclude) { if ($f -match $rx) { $skip = $true; break } }
  if ($skip) { continue }
  $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
  if ($binExt -contains $ext) { continue }
  $text = ''
  try { $text = Get-Content -LiteralPath $f -Raw -Encoding UTF8 } catch { $text = '' }
  if ($null -eq $text) { $text = '' }
  if ($text -ne '' -and $text.Contains($Old)) {
    $text = $text.Replace($Old, $New)
    Set-Content -LiteralPath $f -Value $text -Encoding UTF8
    $changed += $f
    Write-Host ('  patched: ' + $f) -ForegroundColor Green
  }
}
if ($changed.Count -gt 0) {
  git add -A
  git commit -m ('chore: replace repo URL ' + $Old + ' -> ' + $New)
  git push
  Write-Host ('Done. Updated ' + $changed.Count + ' file(s).') -ForegroundColor Green
} else {
  Write-Host 'No files contained the old URL.' -ForegroundColor Cyan
}


