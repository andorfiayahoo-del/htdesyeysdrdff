// gateway.js
// A minimal Unity <-> OpenAI Realtime bridge with sane buffering/commits.
// - Unity sends binary PCM16 audio frames (any common sample rate).
// - We resample to 24kHz mono PCM16 for OpenAI.
// - We append in small chunks, commit when we have >= MIN_COMMIT_MS,
//   and create a response if one isn't already in flight.
// - We play OpenAI's output audio back to Unity, resampled to 48kHz PCM16.
//
// ENV:
//   OPENAI_API_KEY=sk-...           (required)
//   OPENAI_MODEL=gpt-4o-realtime-preview  (optional; default)
//   GATEWAY_PORT=8765               (optional)
//   UNITY_INPUT_RATE=44100          (optional; Unity mic rate if known, default 24000)
//   UNITY_OUTPUT_RATE=48000         (optional; default 48000)
//   VOICE=verse                     (optional)
//   MIN_COMMIT_MS=160               (optional; lower bound commit size)
//   MAX_BUFFER_MS=1600              (optional; safety cap to force commit)
//   COMMIT_INTERVAL_MS=200          (optional; check cadence)
//   LOG_LEVEL=info|debug|trace      (optional)

import { WebSocketServer, WebSocket } from 'ws';

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
if (!OPENAI_API_KEY) {
  console.error('[Gateway][FATAL] Missing OPENAI_API_KEY.');
  process.exit(1);
}

const PORT = Number(process.env.GATEWAY_PORT || 8765);
const MODEL = process.env.OPENAI_MODEL || 'gpt-4o-realtime-preview';
const VOICE = process.env.VOICE || 'verse';

const OA_RATE = 24000; // OpenAI realtime expects 24kHz mono PCM16
const UNITY_IN_RATE = Number(process.env.UNITY_INPUT_RATE || 24000);
const UNITY_OUT_RATE = Number(process.env.UNITY_OUTPUT_RATE || 48000);

const MIN_COMMIT_MS = Number(process.env.MIN_COMMIT_MS || 160);     // OpenAI requires >= ~100ms; we use 160ms
const MAX_BUFFER_MS = Number(process.env.MAX_BUFFER_MS || 1600);    // If we somehow accumulate too much, force commit
const COMMIT_INTERVAL_MS = Number(process.env.COMMIT_INTERVAL_MS || 200);

const LOG_LEVEL = (process.env.LOG_LEVEL || 'info').toLowerCase();
const log = {
  info: (...a) => (['info','debug','trace'].includes(LOG_LEVEL) ? console.log('[Gateway]', ...a) : void 0),
  debug: (...a) => (['debug','trace'].includes(LOG_LEVEL) ? console.log('[Gateway][DEBUG]', ...a) : void 0),
  trace: (...a) => (['trace'].includes(LOG_LEVEL) ? console.log('[Gateway][TRACE]', ...a) : void 0),
  error: (...a) => console.error('[Gateway][ERROR]', ...a),
};

// ---- PCM16 helpers ----
function bytesToMsPCM16(bytes, sampleRate) {
  const samples = bytes / 2; // 16-bit (2 bytes)
  return (samples / sampleRate) * 1000;
}
function msToBytesPCM16(ms, sampleRate) {
  const samples = Math.floor((ms / 1000) * sampleRate);
  return samples * 2;
}
function base64FromBuffer(buf) { return buf.toString('base64'); }
function bufferFromBase64(b64) { return Buffer.from(b64, 'base64'); }

// Linear resampler for PCM16 mono.
// Input: Buffer of little-endian int16, output: Buffer of little-endian int16 at dstRate.
function resamplePCM16Mono(srcBuf, srcRate, dstRate) {
  if (srcRate === dstRate || srcBuf.length === 0) return srcBuf;

  const srcSamples = srcBuf.length / 2;
  const ratio = dstRate / srcRate;
  const dstSamples = Math.max(1, Math.floor(srcSamples * ratio));
  const out = new Int16Array(dstSamples);

  const inView = new Int16Array(srcBuf.buffer, srcBuf.byteOffset, srcSamples);
  let t = 0; // position in source samples
  for (let i = 0; i < dstSamples; i++) {
    const idx = Math.floor(t);
    const frac = t - idx;
    const s0 = inView[idx] ?? 0;
    const s1 = inView[Math.min(idx + 1, srcSamples - 1)] ?? s0;
    out[i] = (s0 + (s1 - s0) * frac) | 0;
    t += 1 / ratio;
  }
  return Buffer.from(out.buffer, out.byteOffset, out.byteLength);
}

// ---- Session wrapper ----
class OAUnitySession {
  constructor(unitySocket) {
    this.unity = unitySocket;
    this.oa = null;

    this.buffer24k = Buffer.alloc(0); // uncommitted PCM16@24kHz
    this.responseInFlight = false;

    this.commitTimer = null;
    this.closed = false;

    this.init();
  }

  msBuffered() {
    return bytesToMsPCM16(this.buffer24k.length, OA_RATE);
  }

  appendUnityAudio(binaryBuf) {
    // Unity sends PCM16 mono. Resample to 24k if needed.
    if (!(binaryBuf instanceof Buffer)) return;
    // Filter out tiny frames (likely keepalives)
    if (binaryBuf.length < 8) {
      log.trace('Ignored tiny binary frame', binaryBuf.length);
      return;
    }

    const inBuf24 = UNITY_IN_RATE === OA_RATE
      ? binaryBuf
      : resamplePCM16Mono(binaryBuf, UNITY_IN_RATE, OA_RATE);

    this.buffer24k = Buffer.concat([this.buffer24k, inBuf24]);
    this._appendToOpenAI(inBuf24);
  }

  _appendToOpenAI(pcm24buf) {
    if (!this.oa || this.oa.readyState !== WebSocket.OPEN) return;
    if (!pcm24buf || pcm24buf.length === 0) return;

    const b64 = base64FromBuffer(pcm24buf);
    const msg = {
      type: 'input_audio_buffer.append',
      audio: b64,
    };
    this._sendOA(msg);
    log.trace(`APPEND -> OA +${pcm24buf.length}B buffered≈${this.msBuffered().toFixed(0)}ms`);
  }

  _commitIfReady(force = false) {
    const ms = this.msBuffered();
    if (!this.oa || this.oa.readyState !== WebSocket.OPEN) return;

    if (force || ms >= MIN_COMMIT_MS) {
      this._sendOA({ type: 'input_audio_buffer.commit' });
      log.debug(`COMMIT -> OA (ms=${ms.toFixed(0)}${force?' force':''})`);
      // After commit, we can ask for a response if not already in flight.
      if (!this.responseInFlight) {
        this.responseInFlight = true;
        this._sendOA({ type: 'response.create' });
        log.debug('response.create -> OA');
      }
      // Clear local buffer (committed)
      this.buffer24k = Buffer.alloc(0);
    }
  }

  _startCommitLoop() {
    if (this.commitTimer) return;
    this.commitTimer = setInterval(() => {
      if (this.closed) return;
      const ms = this.msBuffered();
      if (ms >= MAX_BUFFER_MS) {
        this._commitIfReady(true);
        return;
      }
      if (ms >= MIN_COMMIT_MS) {
        this._commitIfReady(false);
      }
    }, COMMIT_INTERVAL_MS);
  }

  _stopCommitLoop() {
    if (this.commitTimer) {
      clearInterval(this.commitTimer);
      this.commitTimer = null;
    }
  }

  _sendOA(obj) {
    try {
      this.oa.send(JSON.stringify(obj));
    } catch (e) {
      log.error('Send OA failed:', e?.message || e);
    }
  }

  _sendUnityBinary(buf) {
    try {
      if (this.unity && this.unity.readyState === WebSocket.OPEN) {
        this.unity.send(buf, { binary: true });
      }
    } catch (e) {
      log.error('Send Unity failed:', e?.message || e);
    }
  }

  init() {
    // Connect to OpenAI Realtime
    const url = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(MODEL)}`;
    this.oa = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'OpenAI-Beta': 'realtime=v1',
      }
    });

    this.oa.on('open', () => {
      log.info('Realtime WS connected.');
      // Session update: IMPORTANT — input_audio_format must be "pcm16"
      const sessionUpdate = {
        type: 'session.update',
        session: {
          input_audio_format: 'pcm16',
          output_audio_format: 'pcm16',
          voice: VOICE,
          // Optional: let the model speak without being explicitly asked.
          modalities: ['audio', 'text'],
          // If you later want server VAD, uncomment below and remove manual response.create calls.
          // turn_detection: { type: 'server_vad' },
        }
      };
      this._sendOA(sessionUpdate);
      log.debug(`-> OA session.update (input=pcm16@${OA_RATE}, output=pcm16@${OA_RATE}, voice=${VOICE})`);

      // Start periodic commit loop
      this._startCommitLoop();
    });

    this.oa.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        this._handleOAEvent(msg);
      } catch (e) {
        // Some events from OA can be binary audio (rare). Just warn.
        log.trace('OA non-JSON/binary message, ignoring.');
      }
    });

    this.oa.on('close', (code, reason) => {
      log.info(`Realtime WS closed. code=${code} reason=${reason}`);
      this._stopCommitLoop();
      if (!this.closed) {
        try { this.unity?.close(1000, 'OpenAI gone'); } catch {}
      }
    });

    this.oa.on('error', (err) => {
      log.error('OpenAI error:', err?.message || err);
    });

    // Unity socket handlers
    this.unity.on('message', (data, isBinary) => {
      if (isBinary) {
        this.appendUnityAudio(data);
      } else {
        // You can implement simple text control messages from Unity here.
        log.trace('Unity text:', data.toString());
      }
    });

    this.unity.on('close', (code, reason) => {
      log.info(`Unity client disconnected. code=${code} reason=${reason}`);
      this.close();
    });

    this.unity.on('error', (err) => {
      log.error('Unity socket error:', err?.message || err);
      this.close();
    });
  }

  _handleOAEvent(ev) {
    const t = ev?.type;
    if (!t) return;

    switch (t) {
      case 'session.created':
      case 'session.updated':
        log.trace(`OA ▶ ${t}`);
        break;

      case 'response.created':
        log.trace('OA ▶ response.created');
        break;

      case 'response.output_text.delta':
        // If you want, you can forward text to Unity HUD via JSON.
        log.trace('OA ▶ text.delta:', ev.delta);
        break;

      case 'response.output_audio.delta': {
        // Base64 PCM16@24kHz from OpenAI
        const b64 = ev.delta;
        if (b64) {
          const pcm24 = bufferFromBase64(b64);
          const pcmUnity = (UNITY_OUT_RATE === OA_RATE)
            ? pcm24
            : resamplePCM16Mono(pcm24, OA_RATE, UNITY_OUT_RATE);
          this._sendUnityBinary(pcmUnity);
        }
        break;
      }

      case 'response.completed':
        log.debug('OA ▶ response.completed');
        this.responseInFlight = false;
        break;

      case 'response.output_audio.done':
        log.trace('OA ▶ audio.done');
        break;

      case 'error':
        // OpenAI error payload
        log.error('OpenAI error:', JSON.stringify(ev, null, 2));
        // Don’t get stuck
        this.responseInFlight = false;
        break;

      default:
        // Many other minor event types exist; log at trace level
        log.trace('OA ▶', t);
        break;
    }
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this._stopCommitLoop();
    try { this.oa?.close(1000, 'Unity gone'); } catch {}
    try { this.unity?.close(1000, 'bye'); } catch {}
  }
}

// ---- WebSocket server for Unity ----
const wss = new WebSocketServer({ host: '127.0.0.1', port: PORT });

wss.on('listening', () => {
  log.info(`Gateway listening on ws://127.0.0.1:${PORT}`);
});

wss.on('connection', (ws, req) => {
  log.info(`Unity client connected. Total: ${wss.clients.size} | from ${req.socket.remoteAddress}`);
  // Start a new OA session per Unity connection
  new OAUnitySession(ws);
});

wss.on('error', (err) => {
  log.error('WSS error:', err?.message || err);
});
