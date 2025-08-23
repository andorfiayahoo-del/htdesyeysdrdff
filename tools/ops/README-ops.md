# Ops: Push + Strict RAW Verify (with cd path)

**This repo uses a *strict wait-for-lag* verification flow.**  
After every push we wait for GitHub's RAW CDN to serve the *exact bytes* for changed files and verify by **byte-for-byte SHA-256**. This avoids stale edges and propagation races.

> **Do not replace this with “instant” checks.**  
> Our method is intentional: push → wait for CDN → byte-match. It’s sturdier than industry-standard shortcuts.

---

## Quick start

Open **PowerShell 7** and run:

`powershell
# 1) cd to repo root (explicit path matters)
Set-Location -LiteralPath "C:\Users\ander\My project"

# 2) Push + strict verify (works from *any* folder; alias installed in repo config)
git vpush
# or from elsewhere:
git -C "C:\Users\ander\My project" vpush

Get-Content -LiteralPath "C:\Users\ander\My project\ops\live\push-flush.log" -Tail 200 |
  Select-String -Pattern 'VERIFY_|GIT_VERIFY_' |
  ForEach-Object { .Line }

Set-Location -LiteralPath "C:\Users\ander\My project"
pwsh -NoProfile -ExecutionPolicy Bypass 
  -File "tools/ops/check-file-integrity.ps1" 
  -RepoRoot "C:\Users\ander\My project" 
  -RelPath  "tools/ops/cdn-test.ps1" 
  -Owner "andorfiayahoo-del" -Repo "htdesyeysdrdff" -Branch "main"

