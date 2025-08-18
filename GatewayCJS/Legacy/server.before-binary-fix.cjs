// server.cjs — Unity <-> OpenAI Realtime gateway
'use strict';

const WebSocket = require('ws');
const http = require('http');
const os = require('os');

const MODEL = process.env.OPENAI_REALTIME_MODEL || 'gpt-4o-realtime-preview-2024-12-17';
const UNITY_WS_PORT = Number(process.env.UNITY_WS_PORT || 8765);
const HEALTH_PORT = Number(process.env.HEALTH_PORT || 8766);
const OPENAI_URL = `wss://api.openai.com/v1/realtime?model=${MODEL}`;

const mask = k => (k ? `${k.slice(0,4)}…${k.slice(-4)}` : 'missing');
const log  = (...a) => console.log('[Gateway]', ...a);

log(`Boot @ ${new Date().toLocaleTimeString().toLowerCase()}`);
log(`Node: ${process.version} | Platform: ${process.platform}`);
log(`Model: ${MODEL}`);
log(`OPENAI_API_KEY present (masked): ${mask(process.env.OPENAI_API_KEY)}`);
log(`Health endpoint: http://127.0.0.1:${HEALTH_PORT}/health`);
log(`Unity WS listening ws://127.0.0.1:${UNITY_WS_PORT}`);

// --- tiny health server
http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, {'content-type':'application/json'});
    res.end(JSON.stringify({ ok:true, model:MODEL, node:process.version, host:os.hostname(), up:process.uptime() }));
  } else { res.writeHead(404); res.end(); }
}).listen(HEALTH_PORT, '127.0.0.1');

// --- Unity-facing WS
const unityWSS = new WebSocket.Server({ port: UNITY_WS_PORT });

unityWSS.on('connection', (unity) => {
  log('Unity client connected. Total:', unityWSS.clients.size, '| from', unity._socket?.remoteAddress || 'unknown');

  // OpenAI WS
  let openai, readyOpenAI = false;
  const queue = [];
  function sendToOpenAI(obj) {
    const payload = typeof obj === 'string' ? obj : JSON.stringify(obj);
    if (readyOpenAI) openai.send(payload);
    else queue.push(payload);
  }

  // audio accounting + throttles
  let inputHz = 44100;            // default mic rate (Unity says 44100)
  let bytesSinceCommit = 0;
  let appendCount = 0;
  const MIN_COMMIT_MS = 120;      // needs >=100ms; use ~120ms
  const minBytesNeeded = () => Math.ceil((MIN_COMMIT_MS/1000)*inputHz*2); // mono PCM16

  let responseInFlight = false;
  let responseTimer = null;
  const RESPONSE_TIMEOUT_MS = 12000;
  const clearInFlight = () => { responseInFlight = false; if (responseTimer) { clearTimeout(responseTimer); responseTimer=null; } };

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
      while (queue.length) openai.send(queue.shift());
      // keep session.update minimal/valid
      sendToOpenAI({ type:'session.update', session:{ voice:'verse', input_audio_format:'pcm16', output_audio_format:'pcm16' } });
      log('-> OpenAI session.update (in=pcm16, out=pcm16, voice=verse)');
    });

    openai.on('close', (c,r)=>{ readyOpenAI=false; log(`Realtime WS closed. code=${c} reason=${r||''}`); clearInFlight(); });
    openai.on('error', (e)=> log('Realtime WS error:', e?.message || e));

    openai.on('message', (data, isBinary) => {
      if (isBinary) return; // JSON only to Unity
      let evt; try { evt = JSON.parse(data.toString()); } catch { return; }

      // release throttle on end/error
      if (evt.type === 'response.completed' || evt.type === 'response.canceled' || evt.type === 'response.error') clearInFlight();

      // map a few key events back to Unity
      if (evt.type === 'response.output_audio.delta') { unity.send(JSON.stringify({ type:'audio.delta', audio: evt.delta })); return; }
      if (evt.type === 'response.output_audio.done')  { unity.send(JSON.stringify({ type:'audio.end' })); return; }
      if (evt.type === 'response.output_text.delta')  { unity.send(JSON.stringify({ type:'text.delta',  delta: evt.delta || '' })); return; }
      if (evt.type === 'response.completed')          { unity.send(JSON.stringify({ type:'response.completed' })); return; }
      if (evt.type === 'error') {
        log('OpenAI error:', JSON.stringify(evt, null, 2));
        unity.send(JSON.stringify({ type:'error', error: evt.error || evt }));
        return;
      }
    });
  }
  openOpenAI();

  // helper: kick a response if none in flight
  function ensureResponse(voice='verse', instructions) {
    if (responseInFlight) return;
    responseInFlight = true;
    responseTimer = setTimeout(()=>{ log('Response timeout — clearing in-flight guard.'); responseInFlight=false; }, RESPONSE_TIMEOUT_MS);
    sendToOpenAI({
      type: 'response.create',
      response: {
        modalities: ['audio','text'],
        instructions: instructions || 'You are a concise game voice assistant. Keep replies short and helpful.',
        audio: { voice }
      }
    });
    log('-> OpenAI response.create (auto)');
  }

  // --- Unity -> Gateway
  unity.on('message', (data, isBinary) => {
    // 1) Binary frames = raw PCM16 from Unity mic -> base64 + append
    if (isBinary) {
      const len = data.length;
      const b64 = Buffer.from(data).toString('base64');
      bytesSinceCommit += len;
      appendCount++;
      if (appendCount % 25 === 0) log(`APPEND(bin): chunks=${appendCount} buffered≈${Math.floor(bytesSinceCommit/(2*(inputHz/1000)))}ms`);
      sendToOpenAI({ type:'input_audio_buffer.append', audio: b64 });
      return;
    }

    // 2) JSON control messages
    let msg; try { msg = JSON.parse(data.toString()); } catch { log('Dropped Unity msg: not JSON.'); return; }

    switch (msg.type) {
      case 'session.update': {
        // capture mic rate if Unity provides one (do not forward unknown fields to OpenAI)
        if (msg.session) {
          if (typeof msg.session.input_audio_sample_rate_hz === 'number') inputHz = msg.session.input_audio_sample_rate_hz;
          else if (typeof msg.session.mic_rate_hz === 'number')          inputHz = msg.session.mic_rate_hz;
        }
        // forward a clean session.update
        const clean = { type:'session.update', session:{ voice:(msg.session?.voice)||'verse', input_audio_format:'pcm16', output_audio_format:'pcm16' } };
        sendToOpenAI(clean);
        log('-> OpenAI session.update (voice=%s, in/out=pcm16, mic=%sHz)', clean.session.voice, inputHz);
        break;
      }

      case 'input_audio_buffer.append': {
        if (!msg.audio) return;
        const b64 = msg.audio;
        // estimate decoded bytes
        const bytes = Math.floor((b64.length*3)/4) - (b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0);
        bytesSinceCommit += bytes;
        appendCount++;
        if (appendCount % 25 === 0) log(`APPEND(json): chunks=${appendCount} buffered≈${Math.floor(bytesSinceCommit/(2*(inputHz/1000)))}ms`);
        sendToOpenAI({ type:'input_audio_buffer.append', audio: b64 });
        break;
      }

      case 'input_audio_buffer.commit': {
        const need = minBytesNeeded();
        const haveMs = Math.floor(bytesSinceCommit/(2*(inputHz/1000)));
        if (bytesSinceCommit < need) {
          log(`COMMIT skipped (<${MIN_COMMIT_MS}ms). have≈${haveMs}ms`);
        } else {
          sendToOpenAI({ type:'input_audio_buffer.commit' });
          log(`COMMIT ok. sent≈${haveMs}ms (bytes=${bytesSinceCommit})`);
          bytesSinceCommit = 0;
          // kick a response if Unity isn't going to send one
          ensureResponse();
        }
        break;
      }

      case 'response.create': {
        // if Unity explicitly asks, respect it (with in-flight guard)
        if (responseInFlight) { log('Throttle: response already in flight, ignoring duplicate.'); break; }
        responseInFlight = true;
        responseTimer = setTimeout(()=>{ log('Response timeout — clearing in-flight guard.'); responseInFlight=false; }, RESPONSE_TIMEOUT_MS);
        const instructions = msg.response?.instructions || 'You are a concise game voice assistant.';
        const voice = msg.response?.voice || 'verse';
        sendToOpenAI({ type:'response.create', response:{ modalities:['audio','text'], instructions, audio:{ voice } } });
        log('-> OpenAI response.create (unity)');
        break;
      }

      default: {
        // pass-through anything else
        sendToOpenAI(msg);
        break;
      }
    }
  });

  unity.on('close', (code, reason) => {
    log(`Unity client disconnected. code=${code} reason=${reason||'bye'} Total now:${unityWSS.clients.size-1}`);
    if (openai && readyOpenAI) openai.close(1000, 'Unity gone');
  });

  unity.on('error', (err) => log('Unity WS error:', err?.message || err));
});

process.on('uncaughtException', e => console.error('[Gateway] Uncaught:', e));
process.on('unhandledRejection', e => console.error('[Gateway] Unhandled:', e));
