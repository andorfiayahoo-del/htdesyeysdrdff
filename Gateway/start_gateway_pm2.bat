@echo off
cd /d "%~dp0"
pm2 delete unity-gateway >NUL 2>&1
pm2 start server.cjs --name unity-gateway
pm2 save
echo.
echo Started with PM2. View logs with:
echo   pm2 logs unity-gateway --lines 100
