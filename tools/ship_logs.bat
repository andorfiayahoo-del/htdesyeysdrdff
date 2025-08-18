@echo off
setlocal
set SCRIPT_DIR=%~dp0
set OUTDIR=%SCRIPT_DIR%..\LogsOutbox

if not "%LOG_SHIP_DEST%"=="" set OUTDIR=%LOG_SHIP_DEST%

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%ship_logs.ps1" -OutDir "%OUTDIR%"
echo.
echo Done. Output: %OUTDIR%
endlocal
