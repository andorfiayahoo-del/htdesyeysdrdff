// ecosystem.config.js
module.exports = {
  apps: [
    {
      name: 'unity-gateway',
      script: 'server.cjs',
      cwd: __dirname,
      // Do NOT put your API key here — PM2 will inherit your existing env if you use --update-env.
      env: {
        NODE_ENV: 'production',
        UNITY_WS_PORT: 8765,
        HEALTH_PORT: 8766,
        OPENAI_REALTIME_MODEL: 'gpt-4o-realtime-preview-2024-12-17',
        VOICE: 'verse',
        UNITY_SAMPLE_RATE_HZ: 44100,
        OUTPUT_SAMPLE_RATE_HZ: 24000,
        MIN_COMMIT_MS: 100
      },
      autorestart: true,
      watch: false,
      max_restarts: 10,
      restart_delay: 2000,
      time: true
    }
  ]
};
