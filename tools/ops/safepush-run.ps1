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
    # Guard: ensure RID/LiveDir/tx before transcript
    if (-not $rid -or [string]::IsNullOrWhiteSpace($rid)) {
      $rid = (Get-Date).ToString("yyyyMMddTHHmmss.fffffffZ") + "-" + ([guid]::NewGuid().ToString("N"))
    }
    # last-chance: scan entire transcript if still (none)
    if ($errJoined -eq '(none)') {
      try {
        $raw = $null
        if (Test-Path $txPath) { $raw = Get-Content $txPath -Raw -ErrorAction SilentlyContinue }
        if ($raw) {
          # Grab a meaningful single line if present
          $patterns = @(
            'NativeCommandExitException[^\r\n]*',
            'ParserError[^\r\n]*',
            'PS>TerminatingError[^\r\n]*',
            'The running command stopped because[^\r\n]*',
            'At .+?:\d+\s+char:[^\r\n]*'
          )
          foreach($p in $patterns){
            if ($raw -match $p) {
              $errJoined = $matches[0]
              break
            }
          }
          if ($errJoined -eq '(none)') {
            # fallback: first non-empty, non-[step] line in the last 300 chars
            $tailRaw = $raw.Substring([Math]::Max(0, $raw.Length - 300))
            $line = ($tailRaw -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\[step\]\s' } | Select-Object -First 1)
            if ($line) { $errJoined = $line }
          }
        }
      } catch { }
    }
    if (-not $LiveDir -or [string]::IsNullOrWhiteSpace($LiveDir)) {
      $LiveDir = Join-Path $RepoRoot "ops\live"
    }
    if (!(Test-Path $LiveDir)) {
      New-Item -ItemType Directory -Path $LiveDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    # enrich $errJoined from transcript tail if still (none)
    if ($errJoined -eq '(none)') {
      $tailScan = @()
      try { if (Test-Path $txPath) { $tailScan = Get-Content $txPath -Tail 200 -ErrorAction SilentlyContinue } } catch {}
      $firstHit = $null
      foreach($pat in @('ParserError','NativeCommandExitException','TerminatingError','At .*?:\d+ char:','The running command stopped because')) {
        if(-not $firstHit) {
          $hit = $tailScan | Where-Object { $_ -match $pat } | Select-Object -First 1
          if($hit) { $firstHit = $hit }
        }
      }
      if(-not $firstHit -and $tailScan) {
        $firstHit = ($tailScan | Where-Object { $_ -match '\S' } | Select-Object -First 1)
      }
      if($firstHit) { $errJoined = $firstHit }
    }
    if (-not $tx -or [string]::IsNullOrWhiteSpace($tx)) {
      $tx = Join-Path $LiveDir ("transcript_" + $rid + ".log")
    }
    # Guard: ensure error file paths ($errFile/$errorFile)
    if (-not $errFile -or [string]::IsNullOrWhiteSpace($errFile)) {
      $errFile = Join-Path $LiveDir ("error_" + $rid + ".txt")
    }
    if (-not $errorFile -or [string]::IsNullOrWhiteSpace($errorFile)) {
      $errorFile = $errFile
    }
Step "Transcript → $tx"
Start-Transcript -Path $tx | Out-Null
$status = "OK"
try {
  Step "RUN_BEGIN (RID=$rid)"
  Step "EXEC: $Cmd"
    Step "Transcript → $tx"
} catch {
  $status = "ERROR"
  $msg = ($_ | Out-String).Trim()
  Write-LF $errFile @($msg)
  Write-Error $msg
    Step "Transcript → $tx"
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

    Step "Safety publish: ensure latest-* exist for this RID"
    try {
      $liveDirFinal  = if ($LiveDir) { $LiveDir } else { Join-Path $RepoRoot 'ops\live' }
      if (!(Test-Path $liveDirFinal)) { New-Item -ItemType Directory -Path $liveDirFinal -Force -ErrorAction SilentlyContinue | Out-Null }
      $pointerFinal  = Join-Path $liveDirFinal 'latest-pointer.json'
      $latestMdFinal = Join-Path $liveDirFinal 'latest-error.md'
      $txPath        = if ($tx) { $tx } else { Join-Path $liveDirFinal ("transcript_" + $rid + ".log") }
      $errPathLocal  = if ($errFile) { $errFile } else { Join-Path $liveDirFinal ("error_" + $rid + ".txt") }

      $need = $true
      if (Test-Path $pointerFinal) {
        try {
          $p = Get-Content $pointerFinal -Raw | ConvertFrom-Json
          if ($p -and $p.rid -eq $rid) { $need = $false }
        } catch { $need = $true }
      }

      if ($need) {
        $tail = @(); try { if (Test-Path $txPath) { $tail = Get-Content $txPath -Tail 100 } } catch {}
        $errTxt = @(); try { if (Test-Path $errPathLocal) { $errTxt = Get-Content $errPathLocal } } catch {}
        $errJoined = if ($errTxt -and $errTxt.Count -gt 0) { ($errTxt -join ' ') } else { '(none)' }

        $md = @(
          '# Latest Error Snapshot','',
          '**RID:** ' + $rid + '  ',
          '**Status:** ERROR  ',
          '**Error:** ' + $errJoined + '  ','',
          '```text'
        ) + $tail + @('```')

        $enc = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($latestMdFinal, ($md -join "`n"), $enc)

        $headNow = ''; try { $headNow = (git -C "$RepoRoot" rev-parse HEAD).Trim() } catch {}
        $ptr = [pscustomobject]@{
          rid   = $rid; status = "ERROR"; head = $headNow; file = ""; line = "";
          files = [pscustomobject]@{ error_md = $latestMdFinal; transcript = $txPath; error_txt = $errPathLocal }
        }
        $json = ($ptr | ConvertTo-Json -Depth 6)
        [IO.File]::WriteAllText($pointerFinal, $json + "`n", $enc)

        git -C "$RepoRoot" add -- "$latestMdFinal" "$pointerFinal" | Out-Null
        git -C "$RepoRoot" commit -m "ops: safety publish latest-* for rid=$rid" | Out-Null
        if((git -C "$RepoRoot" config --get alias.vpush) -ne $null){ git -C "$RepoRoot" vpush | Out-Null } else { git -C "$RepoRoot" push -u origin main | Out-Null }
        Step "Safety publish completed for rid=$rid"
      } else {
        Step "Safety publish: pointer already up to date for rid=$rid"
      }
    } catch {
      Warn ("Safety publish failed: " + $_.Exception.Message)
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