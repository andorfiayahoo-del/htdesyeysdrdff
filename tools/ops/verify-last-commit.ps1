param(
  [string]$RepoRoot = (Get-Location).Path,
  [string]$Owner    = "",
  [string]$Repo     = "",
  [string]$Branch   = "main",
  [string]$Since    = ""     # optional: verify all changes since this ref (e.g. "origin/main")
)
$ErrorActionPreference = "Stop"

$checker = Join-Path $PSScriptRoot 'check-file-integrity.ps1'
if(!(Test-Path -LiteralPath $checker)){ throw "checker not found: $checker" }

Push-Location -LiteralPath $RepoRoot
try{
  & git rev-parse --is-inside-work-tree *> $null
  if($LASTEXITCODE -ne 0){ throw "Not a git work tree: $RepoRoot" }

  $commit = (& git rev-parse HEAD 2>&1).Trim()
  if([string]::IsNullOrWhiteSpace($commit)){ throw "Could not resolve HEAD" }

  if([string]::IsNullOrWhiteSpace($Since)){
    $changed = (& git diff-tree --no-commit-id --name-only -r HEAD 2>&1) -split "`r?`n"
  } else {
    $changed = (& git diff --name-only $Since HEAD 2>&1) -split "`r?`n"
  }
  $changed = @($changed | Where-Object { $_ -and $_ -notmatch '^(ops/live/|Library/)' })

  Write-Host ("Commit: {0}" -f $commit)
  if($Since){ Write-Host ("Since : {0}" -f $Since) }
  Write-Host ("Files : {0}" -f ($changed.Count))

  if($changed.Count -eq 0){ Write-Host "Nothing to verify."; exit 0 }

  $fail=0; $ok=0; $missing=0
  foreach($rel in $changed){
    Write-Host ("- {0}" -f $rel)
    $argv = @(
      '-NoProfile','-ExecutionPolicy','Bypass','-File', $checker,
      '-RepoRoot', $RepoRoot, '-RelPath', $rel,
      '-Owner', $Owner, '-Repo', $Repo, '-Branch', $Branch
    )
    $proc = Start-Process -FilePath 'pwsh' -ArgumentList $argv -Wait -PassThru -WindowStyle Hidden
    switch ($proc.ExitCode) {
      0 { $ok++ }
      2 { $missing++; $fail++ }
      3 { $fail++ }
      default { $fail++ }
    }
  }

  Write-Host ("Summary: OK={0} Missing={1} Fail={2}" -f $ok,$missing,$fail)
  if($fail -gt 0){ exit 3 } else { exit 0 }
}
finally { Pop-Location }
