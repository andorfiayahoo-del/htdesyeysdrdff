@echo off
setlocal
set "REPO=%CD%"
set "LIVEDIR=%REPO%\ops\live"
if not exist "%LIVEDIR%" mkdir "%LIVEDIR%"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tools\ops\git-health.ps1" -RepoRoot "%REPO%" -LiveDir "%LIVEDIR%" -RemoteName origin -BranchName main
set HC=%ERRORLEVEL%
if not "%HC%"=="0" (
  echo [pre-push] Git health failed (ec=%HC%). Aborting push. 1>&2
  exit /b 1
)
exit /b 0