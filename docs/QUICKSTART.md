# Quickstart

1. Ensure Unity is open on the project.
2. Open PowerShell and run:
   ```powershell
   $RepoRoot = "C:\Users\ander\My project"
   pwsh -NoProfile -File "$RepoRoot\tools\ops\patch-minforce.ps1" -ProjectRoot "$RepoRoot" -TimeoutSec 900
   Get-Content "$RepoRoot\ops\live\push-flush.log" -Tail 80
   ```
3. Confirm:
   - compile focus → busy → idle observed
   - `match.json` shows arrays `mismatched=[]` and `missing=[]` (both empty)
   - `push-flush.log` ends with `VERIFY_STRICT_OK`
