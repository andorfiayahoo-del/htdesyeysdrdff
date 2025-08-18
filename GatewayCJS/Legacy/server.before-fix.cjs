// server.cjs
// CommonJS gateway between Unity (local WS) and OpenAI Realtime WS.
//
// Env you can customize (all optional except OPENAI_API_KEY):
//   OPENAI_API_KEY=sk-...              (required; do NOT paste the key into code)
//   OPENAI_REALTIME_MODEL=gpt-4o-realtime-preview-2024-12-17
//   VOICE=verse
//   UNITY_WS_HOST=127.0.0.1
//   UNITY_WS_PORT=8765
//   HEALTH_PORT=8766
//   COMMIT_MIN_MS=120                  (min audio since last commit)
//   UNITY_INPUT_RATE=44100             (fallback input rate if Unity doesn't send an update)
//   UNITY_INPUT_CHANNELS=1             (fallback channels)

const http = require('http');
const WebSocket = require('ws');

const API_KEY = process.env.OPENAI_API_KEY || '';
if (!API_KEY) {
  console.error('[Gateway] FATAL: OPENAI_API_KEY is not set in the environment.');
  process.exit(1);
}

const MODEL = process.env.OPENAI_REALTIME_MODEL || 'gpt-4o-realtime-preview-2024-12-17';
const VOICE = process.env.VOICE || 'verse';

const UNITY_WS_HOST = process.env.UNITY_WS_HOST || '127.0.0.1';
const UNITY_WS_PORT = Number(process.env.UNITY_WS_PORT || 8765);
const HEALTH_PORT = Number(process.env.HEALTH_PORT || 8766);

const COMMIT_MIN_MS = Number(process.env.COMMIT_MIN_MS || 120);

// Fallback assumptions until Unity tells us otherwise
let unityInputRateDefault = Number(process.env.UNITY_INPUT_RATE || 44100);
let unityInputChannelsDefault = Number(process.env.UNITY_INPUT_CHANNELS || 1);

const nowStr = () =>
  new Date().toLocaleTimeString([], { hour12: true }).toLowerCase();

const maskKey = (k) => (k && k.length > 8 ? `${k.slice(0, 5)}…${k.slice(-4)}` : '(unset)');

function bytesToMs(bytes, sampleRate, channels) {
  // PCM16 = 2 bytes per sample
  const bytesPerSecond = sampleRate * channels * 2;
  return (bytes / bytesPerSecond) * 1000.0;
}

console.log(`[Gateway] Boot @ ${nowStr()}`);
console.log(`[Gateway] Node: ${process.version} | Platform: ${process.platform}`);
console.log(`[Gateway] Model: ${MODEL}`);
console.log(`[Gateway] OPENAI_API_KEY present (masked): ${maskKey(API_KEY)}`);

// -------------------------
// Health HTTP endpoint
// -------------------------
const healthServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        ok: true,
        model: MODEL,
        time: new Date().toISOString(),
      })
    );
  } else {
    res.writeHead(404);
    res.end();
  }
});
healthServer.listen(HEALTH_PORT, '127.0.0.1', () => {
  console.log(`[Gateway] Health endpoint: http://127.0.0.1:${HEALTH_PORT}/health`);
});

// -------------------------
// Unity <-> OpenAI bridge
// -------------------------
const unityWSS = new WebSocket.Server({
  host: UNITY_WS_HOST,
  port: UNITY_WS_PORT,
});

console.log(`[Gateway] Unity WS listening ws://${UNITY_WS_HOST}:${UNITY_WS_PORT}`);

unityWSS.on('connection', (unityWS, req) => {
  const peer = (req && (req.socket.remoteAddress || 'unknown')) || 'unknown';
  console.log(`[Gateway] Unity client connected. Total: ${unityWSS.clients.size} | from ${peer}`);

  // Per-connection mutable state
  let openaiWS = null;
  let openaiReady = false;

  // Track audio since last commit to avoid empty-commit errors
  let bytesSinceCommit = 0;
  let inputRate = unityInputRateDefault;
  let inputChannels = unityInputChannelsDefault;

  // queue Unity → OpenAI messages until the Realtime WS is ready
  const pendingUnityOps = [];

  function sendOpenAI(obj) {
    if (!openaiReady) {
      pendingUnityOps.push(obj);
      return;
    }
    try {
      openaiWS.send(JSON.stringify(obj));
    } catch (e) {
      console.error('[Gateway] Failed to send to OpenAI:', e);
    }
  }

  // Connect to OpenAI Realtime WS
  function connectOpenAI() {
    const url = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(MODEL)}`;
    openaiWS = new WebSocket(url, {
      headers: {
        Authorization: `Bearer ${API_KEY}`,
        'OpenAI-Beta': 'realtime=v1',
      },
    });

    openaiWS.on('open', () => {
      openaiReady = true;
      console.log('[Gateway] Realtime WS connected.');

      // Initial session settings:
      //  - input is simple "pcm16"
      //  - output is PCM16 at 24k (Unity happily resamples if needed)
      //  - voice comes from env (VOICE)
      sendOpenAI({
        type: 'session.update',
        session: {
          // KEEP this a string; earlier error was from sending an object here
          input_audio_format: 'pcm16',

          // Object form is valid for output (includes sample rate)
          output_audio_format: { type: 'pcm16', sample_rate: 24000 },

          // Optional defaults:
          voice: VOICE,

          // IMPORTANT: do NOT send turn_detection:"none"
          // (If needed you can set server_vad/semantic_vad explicitly later.)
          // turn_detection: { type: 'server_vad' }, // <-- only if you really want server VAD
        },
      });

      // Drain any queued ops that arrived from Unity before WS was ready
      while (pendingUnityOps.length) {
        const op = pendingUnityOps.shift();
        try {
          openaiWS.send(JSON.stringify(op));
        } catch (e) {
          console.error('[Gateway] Failed to flush queued op to OpenAI:', e);
        }
      }
    });

    openaiWS.on('message', (data, isBinary) => {
      if (isBinary) {
        // We don't expect binary messages from OpenAI; ignore/log.
        console.warn('[Gateway] Unexpected binary message from OpenAI (ignored).');
        return;
      }

      let msg;
      try {
        msg = JSON.parse(data.toString('utf8'));
      } catch (e) {
        console.warn('[Gateway] Non-JSON message from OpenAI:', e);
        return;
      }

      // Handle audio deltas → forward to Unity as raw PCM16 frames
      if (msg.type === 'response.output_audio.delta' && msg.delta) {
        try {
          const pcm = Buffer.from(msg.delta, 'base64');
          // Forward to Unity as a binary frame
          unityWS.send(pcm, { binary: true });
        } catch (e) {
          console.error('[Gateway] Failed to decode/forward audio delta:', e);
        }
        return;
      }

      // Optional logging for lifecycle/events
      if (msg.type === 'response.completed') {
        console.log('[Gateway] response.completed');
      } else if (msg.type === 'input_audio_buffer.committed') {
        // We could also reset here, but we already reset on commit send.
        // Left for completeness if you prefer to rely on ack.
      } else if (msg.type === 'error' || (msg.error && msg.type === 'response.error')) {
        console.error('[Gateway] OpenAI error:', JSON.stringify(msg, null, 2));
      }
    });

    openaiWS.on('close', (code, reason) => {
      openaiReady = false;
      console.log(`[Gateway] Realtime WS closed. code=${code || ''} reason=${reason?.toString() || ''}`);
    });

    openaiWS.on('error', (err) => {
      console.error('[Gateway] Realtime WS error:', err);
    });
  }

  connectOpenAI();

  // -------------------------
  // Unity → Gateway handling
  // -------------------------
  unityWS.on('message', (data, isBinary) => {
    // Binary from Unity = PCM16 audio chunk
    if (isBinary) {
      const b = Buffer.isBuffer(data) ? data : Buffer.from(data);
      if (!openaiReady) {
        console.warn('[Gateway] Dropped Unity msg: Realtime WS not open yet.');
        return;
      }
      // Forward as base64 payload to OpenAI
      const b64 = b.toString('base64');
      sendOpenAI({
        type: 'input_audio_buffer.append',
        audio: b64,
      });

      bytesSinceCommit += b.length;
      // Helpful debug:
      // console.log(`[Gateway] <- Unity binary ${b.length}b  -> OpenAI input_audio_buffer.append ${b64.length}b64`);
      return;
    }

    // Text from Unity = control JSON
    let msg;
    try {
      msg = JSON.parse(data.toString('utf8'));
    } catch (e) {
      console.warn('[Gateway] Malformed Unity text message (not JSON). Ignored.');
      return;
    }

    const kind = msg?.type || msg?.op;

    switch (kind) {
      case 'session.update': {
        // Allow Unity to adjust session params dynamically
        const desired = msg.session || {};
        // Normalize commonly-sent shorthands
        // Make sure we NEVER send turn_detection:'none'
        if (desired.turn_detection === 'none') delete desired.turn_detection;

        // Normalize input/output shorthand (Unity sometimes sends our own concise shape)
        if (desired.input_audio_format && typeof desired.input_audio_format !== 'string') {
          // Force to "pcm16" string to avoid invalid_type error
          desired.input_audio_format = 'pcm16';
        }
        if (desired.output_audio_format && typeof desired.output_audio_format === 'string') {
          // Accept a plain string, but we prefer explicit sample rate on output
          desired.output_audio_format = { type: desired.output_audio_format, sample_rate: 24000 };
        }

        // Update our local idea of input sample rate/channels if provided by Unity
        if (desired.input_sample_rate) inputRate = Number(desired.input_sample_rate) || inputRate;
        if (desired.input_channels) inputChannels = Number(desired.input_channels) || inputChannels;

        sendOpenAI({
          type: 'session.update',
          session: {
            input_audio_format: 'pcm16',
            output_audio_format: { type: 'pcm16', sample_rate: 24000 },
            voice: desired.voice || VOICE,
            // only include turn_detection if Unity explicitly asks for a supported type
            ...(desired.turn_detection &&
              typeof desired.turn_detection === 'object' &&
              (desired.turn_detection.type === 'server_vad' ||
                desired.turn_detection.type === 'semantic_vad')
              ? { turn_detection: desired.turn_detection }
              : {}),
          },
        });

        console.log(
          `[Gateway] -> OpenAI session.update (in=pcm16@${inputRate}, out=pcm16@24000, voice=${desired.voice || VOICE})`
        );
        break;
      }

      case 'input_audio_buffer.commit':
      case 'commit': {
        // Guard against empty-commit errors by requiring >= COMMIT_MIN_MS since last commit
        const ms = bytesToMs(bytesSinceCommit, inputRate, inputChannels);
        if (ms < COMMIT_MIN_MS) {
          console.log(`[Gateway] Skipping commit (<${COMMIT_MIN_MS}ms). Have ~${ms.toFixed(0)}ms buffered.`);
          // (Optional) you can notify Unity that we ignored the commit, e.g.:
          // unityWS.send(JSON.stringify({ type: 'commit.skipped', msBuffered: ms }));
          break;
        }
        sendOpenAI({ type: 'input_audio_buffer.commit' });
        // reset
        bytesSinceCommit = 0;
        console.log('[Gateway] <- Unity input_audio_buffer.commit  -> OpenAI input_audio_buffer.commit');
        break;
      }

      case 'response.create': {
        // Unity triggers a response; configure for audio modality.
        const response = msg.response || {};
        const instructions = response.instructions || msg.instructions || undefined;

        sendOpenAI({
          type: 'response.create',
          response: {
            modalities: ['audio'],
            // Voice & audio format come from the session; no response.audio here.
            ...(instructions ? { instructions } : {}),
          },
        });

        console.log(`[Gateway] <- Unity response.create  -> OpenAI response.create (audio=pcm16@24000, voice=${VOICE})`);
        break;
      }

      default: {
        // Passthrough for any other structured events Unity might send
        if (kind) {
          sendOpenAI(msg);
        } else {
          console.warn('[Gateway] Unknown Unity message; ignored.');
        }
        break;
      }
    }
  });

  unityWS.on('close', (code, reason) => {
    console.log(
      `[Gateway] Unity client disconnected. code=${code || ''} reason=${reason?.toString() || 'bye'} Total now: ${
        unityWSS.clients.size - 1
      }`
    );
    if (openaiWS && openaiWS.readyState === WebSocket.OPEN) {
      openaiWS.close(1000, 'Unity gone');
    }
  });

  unityWS.on('error', (err) => {
    console.error('[Gateway] Unity WS error:', err);
  });
});

unityWSS.on('close', () => {
  console.log('[Gateway] Unity WS server closed.');
});
