# tools/ops/ContentHelpers.psm1
# Tiny helpers for content writing with explicit newlines.
Set-StrictMode -Version Latest

function Set-ContentLF {
  [CmdletBinding(DefaultParameterSetName='Lines')]
  param(
    [Parameter(Mandatory, Position=0)]
    [string]$Path,

    [Parameter(Mandatory, ParameterSetName='Lines', Position=1)]
    [string[]]$Lines,

    [Parameter(Mandatory, ParameterSetName='Text', Position=1)]
    [string]$Text
  )

  # Ensure directory exists
  $dir = Split-Path -LiteralPath $Path
  if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }

  # If called with -Lines, join with LF. Also normalize any CRLF from caller.
  if ($PSCmdlet.ParameterSetName -eq 'Lines') { $Text = $Lines -join "`n" }
  $Text = $Text -replace "`r`n","`n"

  # Write UTF-8 (no BOM)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

Export-ModuleMember -Function Set-ContentLF
