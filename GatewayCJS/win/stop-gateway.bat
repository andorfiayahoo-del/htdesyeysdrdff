@echo off
pm2 stop unity-gateway 2>NUL
pm2 delete unity-gateway 2>NUL
