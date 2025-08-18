@echo off
setlocal
set SCRIPT_DIR=%~dp0
set TASKNAME=UnityLogShipperHourly
set CMD="\"%SCRIPT_DIR%ship_logs.bat\""

echo Creating/Updating Scheduled Task: %TASKNAME% (Hourly)
schtasks /Create /F /SC HOURLY /MO 1 /TN "%TASKNAME%" /TR %CMD% /RL LIMITED
if %ERRORLEVEL% NEQ 0 (
  echo Failed to create task. Try running this .bat as Administrator.
) else (
  echo Task created. It will run every hour.
)
endlocal
