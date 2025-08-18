module.exports = {
  apps: [{
    name: "unity-gateway",
    script: "server.cjs",
    env: {
      NODE_ENV: "production"
    },
    node_args: "--max-old-space-size=1024",
    max_memory_restart: "800M",
    watch: false,
    autorestart: true
  }]
};
