// server.cjs — Unity <-> OpenAI Realtime gateway
// CommonJS, Node 18+
// - Accepts one Unity WS client at a time (more are queued and disconnected politely)
// - Connects upstream to OpenAI Realtime WS
// - Normalizes session formats to strings: "pcm16" (never objects)
// - Accepts Unity audio either as binary PCM16 frames or as JSON append events
// - Auto-commits after commitEveryMs if audio was appended since last commit
// - Heartbeats upstream to avoid ping timeout
// - Conservative memory policy: does not queue unbounded audio

const WebSocket = require('ws');
const http = require('http');
const url = require('url');
const { TextDecoder } = require('util');

// -------- args & env --------
const args = process.argv.slice(2);
function arg(name, fallback = null) {
  const i = args.indexOf(`--${name}`);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}

const MODEL = arg('model', process.env.OA_MODEL || 'gpt-4o-realtime-preview');
const INPUT_FORMAT = (arg('input-audio-format', 'pcm16') + '').toLowerCase(); // "pcm16"
const OUTPUT_FORMAT = (arg('output-audio-format', 'pcm16') + '').toLowerCase(); // "pcm16"
const VOICE = arg('voice', process.env.OA_VOICE || 'verse');
const PORT = parseInt(arg('port', process.env.PORT || '8765'), 10);
const VERBOSE = args.includes('--verbose') || process.env.VERBOSE === '1';
const COMMIT_MS = parseInt(arg('commit-ms', process.env.COMMIT_MS || '1200'), 10);

const OPENAI_KEY = process.env.OPENAI_API_KEY || process.env.OA_API_KEY || process.env.OAI_KEY;
if (!OPENAI_KEY) {
  console.error('[Gateway][FATAL] Missing OPENAI_API_KEY in environment.');
  process.exit(1);
}

function log(...a) { console.log('[Gateway]', new Date().toISOString() + ':', ...a); }
function warn(...a) { console.warn('[Gateway][WARN]', new Date().toISOString() + ':', ...a); }
function error(...a) { console.error('[Gateway][ERR ]', new Date().toISOString() + ':', ...a); }

// -------- state --------
let currentClient = null;      // Unity
let upstream = null;           // OpenAI
let upstreamPing = null;

let audioDirty = false;        // appended audio since last commit?
let lastAppendTs = 0;
let lastCommitTs = 0;

function clearUpstream() {
  if (upstreamPing) { clearInterval(upstreamPing); upstreamPing = null; }
  if (upstream && upstream.readyState === WebSocket.OPEN) {
    try { upstream.close(1000, 'client disconnect'); } catch {}
  }
  upstream = null;
}

function toUnity(jsonOrBuf) {
  if (!currentClient || currentClient.readyState !== WebSocket.OPEN) return;
  if (Buffer.isBuffer(jsonOrBuf)) {
    currentClient.send(jsonOrBuf, { binary: true });
  } else {
    currentClient.send(typeof jsonOrBuf === 'string' ? jsonOrBuf : JSON.stringify(jsonOrBuf));
  }
}

function toUpstream(json) {
  if (!upstream || upstream.readyState !== WebSocket.OPEN) return false;
  upstream.send(typeof json === 'string' ? json : JSON.stringify(json));
  return true;
}

function sanitizeSessionUpdate(payload) {
  // Force formats to strings; drop any object-y shapes Unity might send
  if (!payload || typeof payload !== 'object') return { type: 'session.update', session: {
    input_audio_format: INPUT_FORMAT,
    output_audio_format: OUTPUT_FORMAT,
    voice: VOICE
  }};

  if (payload.type !== 'session.update') payload.type = 'session.update';
  payload.session = payload.session || {};
  payload.session.input_audio_format = INPUT_FORMAT;
  payload.session.output_audio_format = OUTPUT_FORMAT;
  if (VOICE && !payload.session.voice) payload.session.voice = VOICE;
  // Never forward nested shapes for formats
  if (typeof payload.session.input_audio_format !== 'string') payload.session.input_audio_format = INPUT_FORMAT;
  if (typeof payload.session.output_audio_format !== 'string') payload.session.output_audio_format = OUTPUT_FORMAT;
  return payload;
}

function connectUpstream() {
  const upstreamUrl = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(MODEL)}`;
  upstream = new WebSocket(upstreamUrl, {
    headers: {
      'Authorization': `Bearer ${OPENAI_KEY}`,
      'OpenAI-Beta': 'realtime=v1',
      'User-Agent': 'unity-gateway/1.1'
    },
    perMessageDeflate: false
  });

  upstream.on('open', () => {
    log('Realtime WS connected.');
    // Greet Unity with model info
    toUnity({ type: 'gateway.hello', env_ok: true, oa_model: MODEL, oa_sample_rate: 24000 });
    // Apply authoritative formats/voice
    const sessMsg = sanitizeSessionUpdate({ type: 'session.update', session: { voice: VOICE }});
    toUpstream(sessMsg);
    if (VERBOSE) log('Upstream session.update sent. OA in/out=%dHz | voice=%s', 24000, VOICE);

    toUnity({ type: 'gateway.upstream', status: 'open' });

    // keepalive to avoid 1011 keepalive ping timeout
    upstreamPing = setInterval(() => {
      if (upstream && upstream.readyState === WebSocket.OPEN) {
        try { upstream.ping(); } catch {}
      }
    }, 20000);
  });

  upstream.on('message', (data, isBinary) => {
    if (isBinary) {
      // Directly forward OA audio chunks to Unity
      toUnity(data);
    } else {
      const text = data.toString();
      // Bubble OA events to Unity
      toUnity(text);
      if (VERBOSE && text.length < 1024) log('OA ->', text);
    }
  });

  upstream.on('close', (code, reason) => {
    warn('Realtime WS closed. code=%s reason=%s', code, (reason||'').toString());
    toUnity({ type: 'gateway.upstream', status: 'closed', code, reason: (reason||'').toString() });
    if (upstreamPing) { clearInterval(upstreamPing); upstreamPing = null; }
  });

  upstream.on('error', (e) => {
    error('Realtime WS error:', e.message || e.toString());
  });
}

// Auto commit loop — never commit unless audio appended since last commit
setInterval(() => {
  if (!upstream || upstream.readyState !== WebSocket.OPEN) return;
  const now = Date.now();
  if (audioDirty && (now - lastCommitTs) >= COMMIT_MS) {
    toUpstream({ type: 'input_audio_buffer.commit' });
    lastCommitTs = now;
    audioDirty = false;
    if (VERBOSE) log('-> OA input_audio_buffer.commit');
  }
}, 150);

// -------- Unity WS --------
const wss = new WebSocket.Server({ port: PORT, perMessageDeflate: false }, () => {
  log('Gateway listening on ws://127.0.0.1:%d', PORT);
});

wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress;
  if (currentClient && currentClient.readyState === WebSocket.OPEN) {
    warn('Another Unity client attempted to connect; closing previous and accepting new.');
    try { currentClient.close(1001, 'replaced'); } catch {}
  }
  currentClient = ws;
  audioDirty = false; lastAppendTs = 0; lastCommitTs = 0;

  log('Unity client connected. Total: 1 | from %s', ip);
  toUnity({ type: 'gateway.status', status: 'connected', model: MODEL });

  // connect upstream
  connectUpstream();

  ws.on('message', (data, isBinary) => {
    if (!upstream || upstream.readyState !== WebSocket.OPEN) return;

    if (isBinary) {
      // Interpret as raw PCM16 frame from Unity mic.
      // Forward to OA as base64 append.
      const b64 = Buffer.from(data).toString('base64');
      const ok = toUpstream({ type: 'input_audio_buffer.append', audio: b64 });
      if (ok) {
        audioDirty = true;
        lastAppendTs = Date.now();
        if (VERBOSE) log('Unity -> OA append (bin %d bytes)', data.length);
      }
      return;
    }

    // Text from Unity
    let msg;
    try { msg = JSON.parse(data.toString()); }
    catch {
      warn('Unity sent non-JSON text; ignoring.');
      return;
    }

    if (msg && msg.type === 'session.update') {
      const patched = sanitizeSessionUpdate(msg);
      toUpstream(patched);
      if (VERBOSE) log('Unity -> OA %s (voice=%s, in=%s, out=%s)',
        'session.update', patched.session.voice, patched.session.input_audio_format, patched.session.output_audio_format);
      return;
    }

    // pass-through for normal realtime messages from Unity
    if (msg && typeof msg === 'object') {
      // prevent accidental bad shape for formats
      if (msg.session) {
        if (msg.session.input_audio_format && typeof msg.session.input_audio_format !== 'string') msg.session.input_audio_format = INPUT_FORMAT;
        if (msg.session.output_audio_format && typeof msg.session.output_audio_format !== 'string') msg.session.output_audio_format = OUTPUT_FORMAT;
      }
      toUpstream(msg);
      if (VERBOSE && msg.type) log('Unity -> OA %s', msg.type);
    }
  });

  ws.on('close', (code, reason) => {
    log('Unity client disconnected. code=%s reason=%s', code, (reason||'').toString());
    currentClient = null;
    clearUpstream();
  });

  ws.on('error', (e) => {
    error('Unity WS error:', e.message || e.toString());
  });
});

process.on('SIGINT', () => { log('SIGINT'); clearUpstream(); process.exit(0); });
process.on('SIGTERM', () => { log('SIGTERM'); clearUpstream(); process.exit(0); });
