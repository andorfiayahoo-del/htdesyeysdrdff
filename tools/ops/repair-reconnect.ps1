param(
  [string]$RepoRoot = "C:\Users\ander\My project",
  [string]$Remote   = "origin",
  [string]$Url      = "https://github.com/andorfiayahoo-del/htdesyeysdrdff.git"
)
$ErrorActionPreference='Stop'

if(-not (Test-Path -LiteralPath $RepoRoot)){ throw "RepoRoot not found: $RepoRoot" }
Set-Location -LiteralPath $RepoRoot

# Ensure git repo + main
& git rev-parse --is-inside-work-tree *> $null
if($LASTEXITCODE -ne 0){
  git init  | Out-Null
  git checkout -B main | Out-Null
}

# Ensure remote
$hasRemote = ((git remote) -split "`r?`n") -contains $Remote
if($hasRemote){
  $cur = ((git remote get-url $Remote) | Out-String).Trim()
  if($cur -ne $Url){ git remote set-url $Remote $Url | Out-Null }
}else{
  git remote add $Remote $Url | Out-Null
}

# Ensure hooks path (so post-commit / pre-push are active)
git config core.hooksPath tools/git-hooks | Out-Null

# Prime guard logs once
$live = Join-Path $RepoRoot 'ops\live'
New-Item -ItemType Directory -Force -Path $live | Out-Null
$health = Join-Path $RepoRoot 'tools\ops\git-health.ps1'
if(Test-Path -LiteralPath $health){
  pwsh -NoProfile -ExecutionPolicy Bypass -File $health -RepoRoot $RepoRoot -LiveDir $live -RemoteName $Remote -BranchName main | Out-Null
}

Write-Host "[OK] Repair/Reconnect complete for $RepoRoot"