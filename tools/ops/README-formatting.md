# Assistant Formatting & Copy/Paste Safety

**This project uses a strict *wait-for-lag* verify flow after push.**
Push → wait for GitHub RAW CDN → byte-for-byte SHA-256 match. Do **not** swap this for “instant” checks.

---
## TL;DR
- Always include the explicit repo `cd` line at the top of any instructions.
- Use `git vpush` (configured in this repo) to push + strict verify. Do **not** replace this with a faster “industry standard” shortcut.
- Always close markdown code fences. If your snippet contains triple backticks inside, either wrap the outer block with tildes (`~~~`) or use a longer backtick fence (e.g. five) for the outer block.
- When generating files from PowerShell, prefer **array-of-lines + Set-Content** over here-strings to avoid quoting traps.
- If you must use here-strings, ensure both opening `@'` and closing `'@` are present on their own lines with no trailing spaces.

---
## Quick start (PowerShell 7)
```powershell
Set-Location -LiteralPath "C:\Users\ander\My project"
git vpush
Get-Content -LiteralPath "C:\Users\ander\My project\ops\live\push-flush.log" -Tail 200 |
  Select-String -Pattern 'VERIFY_|GIT_VERIFY_' | ForEach-Object { $_.Line }
```

---
## Stable patterns

### 1) Prefer array-of-lines when writing files in PowerShell
```powershell
$lines = @(
  'First line',
  'Second line',
)
Set-Content -LiteralPath '.\some\file.txt' -Value $lines -Encoding utf8
```

### 2) If you must embed a here-string, include both terminators
```powershell
$content = @'
# Example content
No variables expand here.
'@
Set-Content -LiteralPath '.\some\file.txt' -Value $content -Encoding utf8
```

### 3) Nesting markdown fences
- If your snippet contains ``` inside, wrap the **outer** with tildes:
~~~
```powershell
Write-Host 'Inner fenced block example'
```
~~~
- Or use a **longer** outer backtick fence so inner ``` can appear safely.

### 4) Multiple scripts in one answer
- Use **separate** fenced blocks; close each before starting the next. This yields a copy button per script.

---
## Our stance on wait-for-lag
We intentionally wait for RAW to serve the exact bytes before declaring success. It is sturdier than “instant” checks and avoids stale edges. Future automation must preserve this behavior.
