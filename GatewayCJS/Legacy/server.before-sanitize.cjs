// server.cjs — GatewayCJS
// Bridges Unity <-> OpenAI Realtime over WebSocket
// Safe session.update + robust commit guard + response throttling

'use strict';

const WebSocket = require('ws');
const http = require('http');
const os = require('os');

const MODEL = process.env.OPENAI_REALTIME_MODEL || 'gpt-4o-realtime-preview-2024-12-17';
const UNITY_WS_PORT = Number(process.env.UNITY_WS_PORT || 8765);
const HEALTH_PORT = Number(process.env.HEALTH_PORT || 8766);
const OPENAI_URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`;

const mask = k => (k ? `${k.slice(0, 4)}…${k.slice(-4)}` : 'missing');
const log = (...a) => console.log('[Gateway]', ...a);

// Boot banner
log(`Boot @ ${new Date().toLocaleTimeString().toLowerCase()}`);
log(`Node: ${process.version} | Platform: ${process.platform}`);
log(`Model: ${MODEL}`);
log(`OPENAI_API_KEY present (masked): ${mask(process.env.OPENAI_API_KEY)}`);
log(`Unity WS listening ws://127.0.0.1:${UNITY_WS_PORT}`);
log(`Health endpoint: http://127.0.0.1:${HEALTH_PORT}/health`);

// Health server
http
  .createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(
        JSON.stringify({
          ok: true,
          model: MODEL,
          uptime: process.uptime(),
          node: process.version,
          host: os.hostname(),
        }),
      );
      return;
    }
    res.writeHead(404);
    res.end();
  })
  .listen(HEALTH_PORT, '127.0.0.1');

// Unity-facing WS server
const unityWSS = new WebSocket.Server({ port: UNITY_WS_PORT });

unityWSS.on('connection', (unity) => {
  log('Unity client connected. Total:', unityWSS.clients.size, '| from', unity._socket?.remoteAddress || 'unknown');

  // --- OpenAI WS ---
  let openai;
  let readyOpenAI = false;
  const queueToOpenAI = [];

  // Audio accumulation/commit guard
  let inputHz = 44100; // default; we’ll update from Unity’s session.update if provided
  let bytesSinceCommit = 0;
  const MIN_COMMIT_MS = 180; // OpenAI needs ≥100ms; use ~180ms to be safe
  const minBytesNeeded = () => Math.ceil((MIN_COMMIT_MS / 1000) * inputHz * 2); // mono PCM16, 2 bytes/sample

  // Response throttling (avoid "conversation_already_has_active_response")
  let responseInFlight = false;
  let responseTimer = null;
  const RESPONSE_TIMEOUT_MS = 12000;

  const clearInFlight = () => {
    responseInFlight = false;
    if (responseTimer) { clearTimeout(responseTimer); responseTimer = null; }
  };

  function openOpenAI() {
    openai = new WebSocket(OPENAI_URL, {
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        'OpenAI-Beta': 'realtime=v1',
      },
    });

    openai.on('open', () => {
      readyOpenAI = true;
      log('Realtime WS connected.');

      // Drain queue
      while (queueToOpenAI.length) openai.send(queueToOpenAI.shift());

      // Minimal + valid session.update (no unknown params)
      const sess = {
        type: 'session.update',
        session: {
          voice: 'verse',
          input_audio_format: 'pcm16',
          output_audio_format: 'pcm16',
        },
      };
      openai.send(JSON.stringify(sess));
      log('-> OpenAI session.update (in=pcm16, out=pcm16, voice=verse)');
    });

    openai.on('close', (code, reason) => {
      readyOpenAI = false;
      log(`Realtime WS closed. code=${code} reason=${reason || ''}`);
      clearInFlight();
    });

    openai.on('error', (err) => {
      log('Realtime WS error:', err?.message || err);
    });

    openai.on('message', (data, isBinary) => {
      if (isBinary) {
        // We only forward JSON to Unity
        return;
      }
      let evt;
      try { evt = JSON.parse(data.toString()); } catch { return; }

      // Clear throttle when a response ends
      if (evt.type === 'response.completed' || evt.type === 'response.canceled' || evt.type === 'response.error') {
        clearInFlight();
      }

      // Map OpenAI events to Unity-friendly events
      if (evt.type === 'response.output_audio.delta') {
        // Base64 PCM16 chunk
        unity.send(JSON.stringify({ type: 'audio.delta', audio: evt.delta }));
        return;
      }
      if (evt.type === 'response.output_audio.done') {
        unity.send(JSON.stringify({ type: 'audio.end' }));
        return;
      }
      if (evt.type === 'response.output_text.delta') {
        unity.send(JSON.stringify({ type: 'text.delta', delta: evt.delta || '' }));
        return;
      }
      if (evt.type === 'response.completed') {
        unity.send(JSON.stringify({ type: 'response.completed' }));
        return;
      }
      if (evt.type === 'error') {
        log('OpenAI error:', JSON.stringify(evt, null, 2));
        unity.send(JSON.stringify({ type: 'error', error: evt.error || evt }));
        return;
      }

      // (optional) Forward other informative events if needed:
      // unity.send(JSON.stringify(evt));
    });
  }

  function sendToOpenAI(obj) {
    const payload = typeof obj === 'string' ? obj : JSON.stringify(obj);
    if (readyOpenAI) openai.send(payload);
    else queueToOpenAI.push(payload);
  }

  openOpenAI();

  // --- Unity -> Gateway handling ---
  unity.on('message', (data, isBinary) => {
    if (isBinary) {
      log('Dropped Unity binary frame (expecting JSON).');
      return;
    }
    let msg;
    try { msg = JSON.parse(data.toString()); } catch {
      log('Dropped Unity msg: not JSON.');
      return;
    }

    switch (msg.type) {
      case 'session.update': {
        // Update local inputHz if Unity included it — DO NOT forward unknown fields to OpenAI
        if (msg.session) {
          if (typeof msg.session.input_audio_sample_rate_hz === 'number') {
            inputHz = msg.session.input_audio_sample_rate_hz;
          } else if (typeof msg.session.mic_rate_hz === 'number') {
            inputHz = msg.session.mic_rate_hz;
          }
        }
        const clean = {
          type: 'session.update',
          session: {
            voice: (msg.session && msg.session.voice) || 'verse',
            input_audio_format: 'pcm16',
            output_audio_format: 'pcm16',
          },
        };
        sendToOpenAI(clean);
        log('-> OpenAI session.update (in=pcm16, out=pcm16, voice=%s)', clean.session.voice);
        break;
      }

      case 'input_audio_buffer.append': {
        if (!msg.audio) return;
        const b64 = msg.audio;
        // decode-length estimate: floor(len*3/4) minus padding
        const bytes = Math.floor((b64.length * 3) / 4) - (b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0);
        bytesSinceCommit += bytes;
        sendToOpenAI({ type: 'input_audio_buffer.append', audio: b64 });
        break;
      }

      case 'input_audio_buffer.commit': {
        const need = minBytesNeeded();
        const haveMs = Math.floor(bytesSinceCommit / (2 * (inputHz / 1000)));
        if (bytesSinceCommit < need) {
          log(`Skipping commit (<${MIN_COMMIT_MS}ms). Have ~${haveMs}ms buffered.`);
        } else {
          sendToOpenAI({ type: 'input_audio_buffer.commit' });
          bytesSinceCommit = 0;
          log('<- Unity input_audio_buffer.commit  -> OpenAI input_audio_buffer.commit');
        }
        break;
      }

      case 'response.create': {
        if (responseInFlight) {
          log('Throttle: response already in flight, ignoring duplicate.');
          break;
        }
        responseInFlight = true;
        responseTimer = setTimeout(() => {
          log('Response timeout — clearing in-flight guard.');
          responseInFlight = false;
        }, RESPONSE_TIMEOUT_MS);

        const instructions =
          (msg.response && msg.response.instructions) ||
          'You are a helpful, concise game voice assistant. Keep replies brief.';
        const voice = (msg.response && msg.response.voice) || 'verse';

        const payload = {
          type: 'response.create',
          response: {
            modalities: ['audio', 'text'],
            instructions,
            audio: { voice },
          },
        };
        sendToOpenAI(payload);
        log('<- Unity response.create  -> OpenAI response.create (modalities=audio+text, voice=%s)', voice);
        break;
      }

      default: {
        // Pass-through anything else
        sendToOpenAI(msg);
        break;
      }
    }
  });

  unity.on('close', (code, reason) => {
    log(`Unity client disconnected. code=${code} reason=${reason || 'bye'} Total now: ${unityWSS.clients.size - 1}`);
    if (openai && readyOpenAI) openai.close(1000, 'Unity gone');
  });

  unity.on('error', (err) => {
    log('Unity WS error:', err?.message || err);
  });
});

process.on('uncaughtException', (e) => console.error('[Gateway] Uncaught:', e));
process.on('unhandledRejection', (e) => console.error('[Gateway] Unhandled:', e));
