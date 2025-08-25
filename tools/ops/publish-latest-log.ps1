# tools/ops/publish-latest-log.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [string]$LogPath  = (Join-Path $RepoRoot 'ops\live\push-flush.log')
)

$ErrorActionPreference = 'Stop'
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Warning $m }
function Die($m){ Write-Error $m; exit 1 }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }

if(!(Test-Path $RepoRoot)){ Die "Repo root not found: $RepoRoot" }
if(!(Test-Path (Join-Path $RepoRoot '.git'))){ Die "Not a git repo: $RepoRoot" }
if(!(Test-Path $LogPath)){ Die "Log not found: $LogPath" }

Step "Reading push-flush.log"
[string[]]$all = Get-Content $LogPath -Tail 5000
$lastBegin = $all | Select-String -Pattern 'RUN_BEGIN reason=' | Select-Object -Last 1
if(-not $lastBegin){ Die "No RUN_BEGIN found in tail of $LogPath" }
$ridMatch = [regex]::Match($lastBegin.Line, 'RID=([^\s]+)')
if(-not $ridMatch.Success){ Die "Could not parse RID from: $($lastBegin.Line)" }
$rid = $ridMatch.Groups[1].Value

# Gather only lines for this RID and ensure pure string[] type
$block = @($all | Where-Object { $_ -match ("RID=" + [regex]::Escape($rid)) } | ForEach-Object { [string]$_ })
if(-not $block -or $block.Count -eq 0){ Die "No lines found for RID=$rid" }

$commitMatch = $block | Select-String -Pattern 'VERIFY_STRICT_OK commit=([0-9a-f]{7,40})' | Select-Object -First 1
if($commitMatch){ $commit = ([regex]::Match($commitMatch.Line, 'commit=([0-9a-f]{7,40})')).Groups[1].Value } else { $commit = '' }
$statusLine = $block | Select-String -Pattern 'RUN_END status=([A-Z]+)' | Select-Object -Last 1
if($statusLine){ $statusVal = ([regex]::Match($statusLine.Line, 'RUN_END status=([A-Z]+)')).Groups[1].Value } else { $statusVal = 'UNKNOWN' }
$errLineObj = $block | Select-String -SimpleMatch -Pattern 'ERROR','Error','Exception','Failed','failure' | Select-Object -Last 1
if($errLineObj){ $errText = $errLineObj.Line.Trim() } else { $errText = '' }

$OutDir   = Join-Path $RepoRoot 'ops\live'
$OutLog   = Join-Path $OutDir  'latest-run.log'
$OutMD    = Join-Path $OutDir  'latest-run.md'
$OutIndex = Join-Path $OutDir  'log-index.json'

Step "Writing latest-run.log"
Write-LF $OutLog $block

Step "Writing latest-run.md"
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Latest Verify Run')
$md.Add('')
$md.Add("**RID:** $rid  ")
$md.Add("**Status:** $statusVal  ")
if($commit -and $commit.Length -gt 0){ $md.Add("**Commit:** $commit  ") }
if($errText -and $errText.Length -gt 0){ $md.Add("**Last error hint:** $errText  ") } else { $md.Add("**Last error hint:** none detected  ") }
$md.Add('')
$md.Add('```text')
foreach($line in $block){ $md.Add($line) }   # safer than AddRange with generics
$md.Add('```')
Write-LF $OutMD $md.ToArray()

Step "Updating log-index.json"
if(!(Test-Path $OutIndex)){ Write-LF $OutIndex @("[]") }
try { $idx = Get-Content $OutIndex -Raw | ConvertFrom-Json } catch { $idx = @() }
$entry = [pscustomobject]@{ rid=$rid; status=$statusVal; commit=$commit; updated=(Get-Date).ToString("o") }
$newIdx = ,$entry + ($idx | Select-Object -First 19)
$json = $newIdx | ConvertTo-Json -Depth 5
Write-LF $OutIndex @($json)

Step "Committing snapshot"
git -C "$RepoRoot" add -- $OutLog $OutMD $OutIndex | Out-Null
$summary = "ops: publish latest log RID=$rid status=$statusVal"
if($commit){ $summary += " commit=$commit" }
git -C "$RepoRoot" commit -m $summary | Out-Null

$hasVpush = (git -C "$RepoRoot" config --get alias.vpush) -ne $null
if($hasVpush){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }

Step "Published latest-run artifacts"
Write-Host (" - " + $OutLog.Replace($RepoRoot, ""))
Write-Host (" - " + $OutMD.Replace($RepoRoot, ""))
Write-Host (" - " + $OutIndex.Replace($RepoRoot, ""))