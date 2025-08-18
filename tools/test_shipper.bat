@echo off
setlocal
call "%~dp0ship_logs.bat"
if exist "%~dp0..\LogsOutbox" start "" "%~dp0..\LogsOutbox"
endlocal
