// Server/gateway.js
// A tiny WS proxy between Unity <-> OpenAI Realtime WS that fixes common pitfalls:
// - Forces session.input_audio_format / output_audio_format to string values ("pcm16").
// - Uses a reliable model alias by default: gpt-4o-realtime-preview.
// - Guards commits to avoid "input_audio_buffer_commit_empty".
//
// Binary frames from downstream are forwarded as-is upstream. Text frames are inspected.
// If a text message is a JSON with type = 'session.update', we coerce formats to strings.
//
// Usage:
//   node gateway.js --model gpt-4o-realtime-preview --port 8765 --min-commit-ms 120
//   (or edit config.json / env vars)
//
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

// ------------ Load config -------------
const cfgPath = path.join(__dirname, 'config.json');
let fileCfg = {};
try { fileCfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch {}

const argv = process.argv.slice(2);
function arg(name, def) {
  const i = argv.indexOf(`--${name}`);
  if (i >= 0 && i + 1 < argv.length) return argv[i + 1];
  return def;
}

const CONFIG = {
  model: process.env.REALTIME_MODEL || arg('model', fileCfg.model || 'gpt-4o-realtime-preview'),
  port: parseInt(process.env.PORT || arg('port', fileCfg.listen_port || 8765), 10),
  minCommitMs: parseInt(process.env.MIN_COMMIT_MS || arg('min-commit-ms', fileCfg.min_commit_ms || 120), 10),
  inputAudioFormat: process.env.INPUT_AUDIO_FORMAT || (fileCfg.session && fileCfg.session.input_audio_format) || 'pcm16',
  outputAudioFormat: process.env.OUTPUT_AUDIO_FORMAT || (fileCfg.session && fileCfg.session.output_audio_format) || 'pcm16',
  upstreamUrl: process.env.REALTIME_URL || `wss://api.openai.com/v1/realtime?model=`,
  apiKey: process.env.OPENAI_API_KEY || '',
};
if (!CONFIG.apiKey) {
  console.error('[Gateway] Missing OPENAI_API_KEY');
  process.exit(1);
}

console.log(`[Gateway] Config: model=${CONFIG.model} port=${CONFIG.port} minCommitMs=${CONFIG.minCommitMs} inFmt=${CONFIG.inputAudioFormat} outFmt=${CONFIG.outputAudioFormat}`);

// ------------ Server ------------------
const wss = new WebSocket.Server({ port: CONFIG.port });

wss.on('connection', (downstream, req) => {
  console.log('[Gateway] Downstream connected from', req.socket.remoteAddress);

  const upstreamHeaders = {
    'Authorization': `Bearer ${CONFIG.apiKey}`,
    'OpenAI-Beta': 'realtime=v1',
  };
  const upstream = new WebSocket(`${CONFIG.upstreamUrl}${encodeURIComponent(CONFIG.model)}`, { headers: upstreamHeaders });

  let bytesSinceLastCommit = 0;
  let lastAppendAt = 0;
  let upstreamOpen = false;
  let ready = false;

  upstream.on('open', () => {
    upstreamOpen = true;
    console.log('[Gateway] Upstream connected');
    // Send an initial session.update to enforce formats
    const init = {
      type: 'session.update',
      session: {
        input_audio_format: String(CONFIG.inputAudioFormat),
        output_audio_format: String(CONFIG.outputAudioFormat),
      },
    };
    upstream.send(JSON.stringify(init));
    ready = true;
  });

  upstream.on('close', (code, reason) => {
    console.log('[Gateway] Upstream closed', code, reason.toString());
    try { downstream.close(); } catch {}
  });

  upstream.on('error', (err) => {
    console.error('[Gateway] Upstream error:', err.message);
    try { downstream.send(JSON.stringify({ type: 'error', error: { message: err.message } })); } catch {}
  });

  upstream.on('message', (data, isBinary) => {
    if (isBinary) {
      // forward audio down
      try { downstream.send(data, { binary: true }); } catch {}
    } else {
      try { downstream.send(data.toString()); } catch {}
    }
  });

  downstream.on('close', () => {
    console.log('[Gateway] Downstream closed');
    try { upstream.close(); } catch {}
  });

  downstream.on('error', (err) => {
    console.error('[Gateway] Downstream error:', err.message);
    try { upstream.close(); } catch {}
  });

  downstream.on('message', (data, isBinary) => {
    if (!upstreamOpen) return;

    if (isBinary) {
      // Treat as raw PCM16 audio chunk following an append marker
      bytesSinceLastCommit += data.length;
      lastAppendAt = Date.now();
      try { upstream.send(data, { binary: true }); } catch {}
      return;
    }

    // Interpret text as JSON if possible
    let text = data.toString();
    let msg = null;
    try { msg = JSON.parse(text); } catch {}
    if (!msg || typeof msg !== 'object') {
      // passthrough non-JSON
      try { upstream.send(text); } catch {}
      return;
    }

    const type = msg.type || (msg.session ? 'session.update' : null);

    if (type === 'session.update') {
      if (!msg.session) msg.session = {};
      // Force string formats
      msg.session.input_audio_format = String(CONFIG.inputAudioFormat);
      msg.session.output_audio_format = String(CONFIG.outputAudioFormat);
      try { upstream.send(JSON.stringify(msg)); } catch {}
      return;
    }

    if (type === 'input_audio_buffer.commit') {
      // Guard: ensure we actually appended >= minCommitMs worth of audio.
      // We can't know the exact sample rate here, but OpenAI enforces a minimum;
      // this guard eliminates empty commits entirely.
      if (bytesSinceLastCommit <= 0) {
        const err = {
          type: 'error',
          error: {
            type: 'invalid_request_error',
            code: 'input_audio_buffer_commit_empty',
            message: 'Guarded: received commit with no appended audio.'
          }
        };
        try { downstream.send(JSON.stringify(err)); } catch {}
        return;
      }
      // Also guard a small time window to reduce 0ms buffers
      const elapsed = Date.now() - lastAppendAt;
      if (elapsed < CONFIG.minCommitMs) {
        setTimeout(() => {
          try { upstream.send(JSON.stringify(msg)); } catch {}
          bytesSinceLastCommit = 0;
        }, CONFIG.minCommitMs - elapsed);
      } else {
        try { upstream.send(JSON.stringify(msg)); } catch {}
        bytesSinceLastCommit = 0;
      }
      return;
    }

    // Normal passthrough
    try { upstream.send(JSON.stringify(msg)); } catch {}
  });
});

console.log(`[Gateway] Listening on ws://127.0.0.1:${CONFIG.port}`);
