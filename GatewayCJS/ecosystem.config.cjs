// ecosystem.config.cjs — PM2 config
module.exports = {
  apps: [{
    name: 'unity-gateway',
    script: 'server.cjs',
    node_args: '--max-old-space-size=512',
    env: {
      OPENAI_API_KEY: process.env.OPENAI_API_KEY,
      OA_MODEL: 'gpt-4o-realtime-preview'
    },
    args: [
      '--model', 'gpt-4o-realtime-preview',
      '--input-audio-format', 'pcm16',
      '--output-audio-format', 'pcm16',
      '--port', '8765',
      '--verbose'
    ]
  }]
}
