param([string]$RepoRoot = (Get-Location).Path)

$Handover = Join-Path $RepoRoot "docs\HANDOVER.md"
$Readme   = Join-Path $RepoRoot "README.md"

function Write-Utf8Lf {
  [CmdletBinding(DefaultParameterSetName='Text')]
  param(
    [Parameter(Mandatory,Position=0)] [string]$Path,
    [Parameter(Mandatory,ParameterSetName='Text',Position=1)] [string]$Text
  )
  $dir = Split-Path -LiteralPath $Path
  if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $Text = ($Text -replace "`r`n","`n")
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $utf8)
}

# Ensure docs folder exists
[IO.Directory]::CreateDirectory((Split-Path -LiteralPath $Handover)) | Out-Null

if (Test-Path -LiteralPath $Handover) {
  $text = Get-Content -LiteralPath $Handover -Raw
} else {
  $text = (@(
    "# Handover & Assistant Guide (Canonical)",
    "",
    "Handover was missing; created a minimal placeholder. See repo history for the canonical text.",
    "",
    "Default operating mode: JDI (Just Do It) for low-risk, reversible changes."
  ) -join "`n")
}
Write-Utf8Lf -Path $Handover -Text $text

# Ensure README links to handover
if (Test-Path -LiteralPath $Readme) {
  $existing = Get-Content -LiteralPath $Readme -Raw
  if ($existing -notmatch [regex]::Escape("docs/HANDOVER.md")) {
    $append = @("", "---", "", "## Handover & Assistant Guide", "", "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences.") -join "`n"
    $updated = ($existing.TrimEnd() + "`n" + $append + "`n")
    Write-Utf8Lf -Path $Readme -Text $updated
  }
} else {
  $r = @("# Project", "", "See **[docs/HANDOVER.md](docs/HANDOVER.md)** for the canonical operations guide, default JDI mode, and owner preferences.") -join "`n"
  Write-Utf8Lf -Path $Readme -Text $r
}