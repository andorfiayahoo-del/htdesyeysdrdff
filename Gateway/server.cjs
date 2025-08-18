/* eslint-disable no-console */
// Robust Unity <-> OpenAI Realtime gateway
// - Fixes invalid session.input_audio_format type (uses strings, not objects)
// - Eliminates unbounded buffering of audio (drops when upstream back-pressures or is closed)
// - Adds ping keepalives to prevent 1011 timeouts
// - Commits audio on a timer without piling up data in memory
// - Sanitizes/forwards session.update from Unity (voice/instructions only)

'use strict';

const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const CONFIG_PATH = path.join(__dirname, 'config.json');
const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

const PORT = Number(cfg.port || 8765);
const OA_MODEL = String(cfg.model || 'gpt-4o-realtime-preview');
const VOICE = String(cfg.voice || 'verse');
const KEEPALIVE_SEC = Number(cfg.keepalive_sec || 15);
const COMMIT_MS = Number(cfg.commit_ms || 1200);
const MAX_BUFFERED_BYTES = Number(cfg.max_buffered_bytes || 2 * 1024 * 1024); // cap upstream ws buffer
const OPENAI_HOST = (cfg.openai && cfg.openai.url) || 'wss://api.openai.com/v1/realtime';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

if (!OPENAI_API_KEY) {
  console.error('[Gateway][FATAL] Missing OPENAI_API_KEY in environment.');
  process.exit(1);
}

const wss = new WebSocket.Server({ port: PORT, perMessageDeflate: false });
console.log(`[Gateway] Listening on ws://127.0.0.1:${PORT}`);

function nowISO() {
  return new Date().toISOString();
}

wss.on('connection', (unity, req) => {
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').toString();
  console.log(`[Gateway] ${nowISO()}: Unity client connected. Total: ${wss.clients.size} | from ${ip}`);

  let unityOpen = true;

  // Connect upstream to OpenAI Realtime
  const upstream = new WebSocket(`${OPENAI_HOST}?model=${encodeURIComponent(OA_MODEL)}`, {
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'OpenAI-Beta': 'realtime=v1'
    }
  });

  let upstreamOpen = false;
  let upstreamPingTimer = null;
  let commitTimer = null;
  let lastAppendAt = 0;
  let droppedFrames = 0;

  function startUpstreamKeepalive() {
    if (upstreamPingTimer) return;
    upstreamPingTimer = setInterval(() => {
      if (upstream.readyState === WebSocket.OPEN) {
        try { upstream.ping(); } catch {}
      }
    }, KEEPALIVE_SEC * 1000);
  }
  function stopUpstreamKeepalive() {
    if (upstreamPingTimer) { clearInterval(upstreamPingTimer); upstreamPingTimer = null; }
  }

  function startCommitTimer() {
    if (commitTimer) return;
    commitTimer = setInterval(() => {
      if (!upstreamOpen) return;
      // Only commit if something has been appended recently (avoid pointless commits)
      if (Date.now() - lastAppendAt >= COMMIT_MS && lastAppendAt !== 0) {
        try {
          upstream.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
          lastAppendAt = 0;
        } catch {}
      }
    }, COMMIT_MS);
  }
  function stopCommitTimer() {
    if (commitTimer) { clearInterval(commitTimer); commitTimer = null; }
  }

  upstream.on('open', () => {
    upstreamOpen = true;
    console.log(`[Gateway] ${nowISO()}: Realtime WS connected.`);

    // Apply a clean session.update with string formats (fixes invalid_type)
    const sessionUpdate = {
      type: 'session.update',
      session: {
        input_audio_format: 'pcm16',
        output_audio_format: 'pcm16',
        voice: VOICE
      }
    };
    upstream.send(JSON.stringify(sessionUpdate));
    unity.send(JSON.stringify({ type: 'gateway.upstream', status: 'open' }));

    startUpstreamKeepalive();
    startCommitTimer();
  });

  upstream.on('pong', () => {
    // keepalive ack; nothing to do
  });

  upstream.on('message', (data, isBinary) => {
    // Forward upstream messages verbatim to Unity.
    // (Unity client already parses gateway text)
    try {
      unity.send(data, { binary: isBinary });
    } catch {}
  });

  upstream.on('close', (code, reasonBuf) => {
    upstreamOpen = false;
    stopUpstreamKeepalive();
    stopCommitTimer();
    const reason = reasonBuf ? reasonBuf.toString() : '';
    console.warn(`[Gateway][WARN] ${nowISO()}: Realtime WS closed. code=${code} reason=${reason || '(none)'}`);
    try { unity.send(JSON.stringify({ type: 'gateway.upstream', status: 'closed', code, reason })); } catch {}
  });

  upstream.on('error', (err) => {
    console.warn(`[Gateway][WARN] ${nowISO()}: Upstream error: ${err && err.message ? err.message : err}`);
    try { unity.send(JSON.stringify({ type: 'error', scope: 'upstream', message: String(err && err.message || err) })); } catch {}
  });

  // Unity keepalive pings (helps detect dead sockets)
  const unityPing = setInterval(() => {
    if (unity.readyState === WebSocket.OPEN) {
      try { unity.ping(); } catch {}
    }
  }, KEEPALIVE_SEC * 1000);

  unity.on('pong', () => {});

  unity.on('message', (data, isBinary) => {
    if (!unityOpen) return;

    if (isBinary) {
      // Binary is PCM16 audio from Unity. Stream straight through; don't buffer in arrays.
      if (!upstreamOpen) {
        droppedFrames++;
        return; // upstream not ready; drop to avoid heap growth
      }
      if (typeof upstream.bufferedAmount === 'number' && upstream.bufferedAmount > MAX_BUFFERED_BYTES) {
        droppedFrames++;
        return; // backpressure: drop this frame instead of piling up
      }
      const b64 = Buffer.from(data).toString('base64');
      try {
        upstream.send(JSON.stringify({ type: 'input_audio_buffer.append', audio: b64 }));
        lastAppendAt = Date.now();
      } catch (e) {
        // ignore; if this fails frequently we'll see upstream.close soon
      }
      return;
    }

    // Text messages
    let msg = null;
    try { msg = JSON.parse(data.toString()); } catch {
      // ignore malformed
      return;
    }

    if (!msg || typeof msg !== 'object') return;

    switch (msg.type) {
      case 'session.update': {
        const s = msg.session || {};
        // sanitize: only forward safe fields and force formats to strings
        const clean = {
          type: 'session.update',
          session: {
            voice: s.voice || VOICE,
            instructions: s.instructions,
            input_audio_format: 'pcm16',
            output_audio_format: 'pcm16'
          }
        };
        if (upstream.readyState === WebSocket.OPEN) {
          upstream.send(JSON.stringify(clean));
          console.log(`[Gateway] ${nowISO()}: Upstream session.update sent. OA in/out=%dHz | Unity in=%dHz | voice=%s`, 24000, s.input_sample_rate || 44100, clean.session.voice);
        }
        break;
      }
      case 'response.cancel':
      case 'input_audio_buffer.commit':
      case 'response.create': {
        if (upstream.readyState === WebSocket.OPEN) {
          upstream.send(JSON.stringify(msg));
        }
        break;
      }
      default: {
        // For any other control/event, forward as-is if upstream is open.
        if (upstream.readyState === WebSocket.OPEN) {
          upstream.send(JSON.stringify(msg));
        }
        break;
      }
    }
  });

  unity.on('close', (code, reasonBuf) => {
    unityOpen = false;
    clearInterval(unityPing);
    const reason = reasonBuf ? reasonBuf.toString() : '';
    console.log(`[Gateway] ${nowISO()}: Unity client disconnected. code=${code} reason=${reason} Total now:${wss.clients.size - 1}`);
    try { upstream.close(); } catch {}
  });

  unity.on('error', (err) => {
    console.warn(`[Gateway][WARN] ${nowISO()}: Unity socket error: ${err && err.message ? err.message : err}`);
  });
});
