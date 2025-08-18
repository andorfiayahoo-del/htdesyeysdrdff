Gateway (Unity <-> OpenAI Realtime)
===================================
Files:
- server.cjs
- package.json
- .env.example
- start_gateway_node.bat
- start_gateway_pm2.bat

First time:
  cd /d "C:\Users\ander\My project\Gateway"
  npm install

Run (foreground):
  start_gateway_node.bat

Run (background with PM2):
  start_gateway_pm2.bat
  pm2 logs unity-gateway --lines 100
