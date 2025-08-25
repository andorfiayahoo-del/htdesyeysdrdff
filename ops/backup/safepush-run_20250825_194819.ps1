# tools/ops/safepush-run.ps1
param(
  [string]$RepoRoot = 'C:\Users\ander\My project',
  [Parameter(Mandatory=$true)][string]$Cmd
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
function Step($m){ Write-Host "[step] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Warning $m }
function Write-LF([string]$Path,[string[]]$Lines){ $enc = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($Path, ($Lines -join "`n"), $enc) }
if(!(Test-Path $RepoRoot)){ throw "Repo root not found: $RepoRoot" }
Step "Transcript → $tx"
Start-Transcript -Path $tx | Out-Null
$status = "OK"
try {
  Step "RUN_BEGIN (RID=$rid)"
  Step "EXEC: $Cmd"
  $null = Invoke-Expression $Cmd
} catch {
  $status = "ERROR"
  $msg = ($_ | Out-String).Trim()
  Write-LF $errFile @($msg)
  Write-Error $msg
} finally {
  try { Stop-Transcript | Out-Null } catch { }
  if($status -ne "OK"){
    Step "Publishing latest-error.md (RID-targeted, non-fatal)"
    $pub      = Join-Path (Join-Path $RepoRoot 'tools\ops') 'publish-latest-error.ps1'
    $latestMD = Join-Path $LiveDir 'latest-error.md'
    $pointer  = Join-Path $LiveDir 'latest-pointer.json'
    $pubOK    = $false

    if(Test-Path $pub){
      $oldNative = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
      try {
        # Remove stale artifacts so they can't mask a failed refresh
        foreach($p in @($latestMD,$pointer)){ try { if(Test-Path $p){ Remove-Item $p -Force } } catch {} }

        # Call publisher with explicit RID and force a 0 exit in the child
        & pwsh -NoProfile -ExecutionPolicy Bypass -Command "& { & `"$pub`" -RepoRoot `"$RepoRoot`" -Rid `"$rid`"; exit 0 }" | Out-Null
        $pubOK = $true
      } catch {
        Warn ("publisher exception: " + $_.Exception.Message)
      } finally {
        $PSNativeCommandUseErrorActionPreference = $oldNative
      }
    } else {
      Warn "publisher script not found at $pub"
    }

    # Verify pointer rid matches this run; if not, synthesize conservative latest-*
    $needSynth = $true
    if(Test-Path $pointer){
      try {
        $ptrObj = Get-Content $pointer -Raw | ConvertFrom-Json
        if($ptrObj -and $ptrObj.rid -eq $rid){ $needSynth = $false }
      } catch { $needSynth = $true }
    }

    if($needSynth){
      $tail = @(); try { $tail = Get-Content $tx -Tail 80 } catch { }
      $errTxt = @(); try { if(Test-Path $errFile){ $errTxt = Get-Content $errFile } } catch { }
      $errJoined = if ($errTxt -and $errTxt.Count -gt 0) { ($errTxt -join ' ') } else { '(none)' }
      $md = @(
        '# Latest Error Snapshot','',
        '**RID:** ' + $rid + '  ',
        '**Status:** ERROR  ',
        '**Error:** ' + $errJoined + '  ','',
        '```text'
      ) + $tail + @('```')
      $enc = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($latestMD, ($md -join "`n"), $enc)

      $head = ''; try { $head = (git -C "$RepoRoot" rev-parse HEAD).Trim() } catch { }
      $ptr = [pscustomobject]@{
        rid   = $rid; status = "ERROR"; head = $head; file = ""; line = "";
        files = [pscustomobject]@{ error_md = $latestMD; transcript = $tx; error_txt = $errFile }
      }
      $json = ($ptr | ConvertTo-Json -Depth 6)
      [IO.File]::WriteAllText($pointer, $json + "`n", $enc)
        Step "publisher fallback synthesized latest-* for rid=$rid"
    }
    Step "Committing error artifacts"
    try {
      $toAdd = New-Object System.Collections.Generic.List[string]
      if(Test-Path $latestMD){ $toAdd.Add($latestMD) }
      if(Test-Path $pointer){  $toAdd.Add($pointer) }
      $tfs = Get-ChildItem -Path $LiveDir -Filter 'transcript_*.log' -ErrorAction SilentlyContinue
      $efs = Get-ChildItem -Path $LiveDir -Filter 'error_*.txt' -ErrorAction SilentlyContinue
      foreach($f in @($tfs + $efs)){ $toAdd.Add($f.FullName) }
      foreach($p in $toAdd){ git -C "$RepoRoot" add -- $p | Out-Null }
      $changes = git -C "$RepoRoot" status --porcelain
      if($changes){
        git -C "$RepoRoot" commit -m ("ops: ERROR RID=" + $rid + " (safepush)") | Out-Null
        $hasVpush = (git -C "$RepoRoot" config --get alias.vpush) -ne $null
        if($hasVpush){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }
      } else { Warn "nothing to commit (already captured?)" }
    } catch { Warn ("commit/push failure: " + $_.Exception.Message) }
  }
  Step "RUN_END status=$status RID=$rid"
  if($status -ne "OK"){ exit 2 }
}

Step "Finalize: update latest-pointer head to current HEAD"
try {
  # Resolve live dir & pointer paths safely (work even if earlier vars are null)
  $liveDirFinal = if ($LiveDir) { $LiveDir } else { Join-Path $RepoRoot 'ops\live' }
  $pointerFinal = if ($pointer) { $pointer } else { Join-Path $liveDirFinal 'latest-pointer.json' }

  if (Test-Path $pointerFinal) {
    $headNow = (git -C "$RepoRoot" rev-parse HEAD).Trim()
    $obj = Get-Content $pointerFinal -Raw | ConvertFrom-Json
    if ($obj) {
      $obj.head = $headNow
      $json = ($obj | ConvertTo-Json -Depth 6)
      $enc = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($pointerFinal, $json + "`n", $enc)
      git -C "$RepoRoot" add -- "$pointerFinal" | Out-Null
      git -C "$RepoRoot" commit -m "ops: pointer head synced to post-run HEAD" | Out-Null
      if((git -C "$RepoRoot" config --get alias.vpush) -ne $null){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }
      Step "Pointer head updated to post-run HEAD"
    } else {
      Step "Finalize: pointer JSON unreadable — skipping update"
    }
  } else {
    Step "Finalize: no pointer file found — skipping"
  }
} catch {
  Warn ("Finalize head update failed: " + $_.Exception.Message)
}