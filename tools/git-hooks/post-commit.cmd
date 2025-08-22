@echo off
setlocal
set "REPO=%CD%"
set "LIVEDIR=%REPO%\ops\live"
if not exist "%LIVEDIR%" mkdir "%LIVEDIR%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tools\ops\git-sync.ps1" -RepoRoot "%REPO%" -LiveDir "%LIVEDIR%" -Reason "post-commit"
exit /b 0