$ErrorActionPreference = 'Stop'
$Old = 'https://github.com/andorfiayahoo-del/unity-voice-realtime'
$New = 'https://github.com/andorfiayahoo-del/htdesyeysdrdff'
Write-Host ('Replacing repo URL: ' + $Old + '  -->  ' + $New) -ForegroundColor Yellow

# Derive repo root from this script's directory; fall back to git, then CWD
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..')).Path
try {
  $gitRoot = (git -C $root rev-parse --show-toplevel 2>$null)
  if ($gitRoot) { $root = $gitRoot.Trim() }
} catch {}

Set-Location $root

$exclude = @('^.git/','^Library/','^Temp/','^Obj/','^Build(s)?/','^Logs/','^Packages/','^UserSettings/','.github/')
$binExt = @('.png','.jpg','.jpeg','.gif','.bmp','.ico','.dll','.exe','.pdf','.docx','.zip','.7z','.mp3','.mp4','.wav','.ogg','.fbx','.obj','.unitypackage')
$changed = @()

# Prefer git ls-files; otherwise fallback to recursive enumeration
$files = @()
try { $files = git ls-files } catch { $files = Get-ChildItem -Recurse -File | % { $_.FullName.Substring($root.Length+1).Replace('\','/') } }

foreach ($f in $files) {
  $skip = $false
  foreach ($rx in $exclude) { if ($f -match $rx) { $skip = $true; break } }
  if ($skip) { continue }
  $full = Join-Path $root ($f -replace '/', '\')
  $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
  if ($binExt -contains $ext) { continue }
  $text = ''
  try { $text = Get-Content -LiteralPath $full -Raw -Encoding UTF8 } catch { $text = '' }
  if ($null -eq $text) { $text = '' }
  if ($text -ne '' -and $text.Contains($Old)) {
    $text = $text.Replace($Old, $New)
    Set-Content -LiteralPath $full -Value $text -Encoding UTF8
    $changed += $f
    Write-Host ('  patched: ' + $f) -ForegroundColor Green
  }
}

if ($changed.Count -gt 0) {
  try { git add -A; git commit -m ('chore: replace repo URL ' + $Old + ' -> ' + $New); git push } catch { }
  Write-Host ('Done. Updated ' + $changed.Count + ' file(s).') -ForegroundColor Green
} else {
  Write-Host 'No files contained the old URL.' -ForegroundColor Cyan
}

