/* eslint-disable */
'use strict';

/**
 * Realtime Smoke Test (VERBOSE, fixed)
 * - Prints events
 * - Saves PCM16@24kHz audio to ping.wav
 * - Treats both `response.done` and `response.completed` as completion
 * Env: OPENAI_API_KEY
 */

const WS = require('ws');
const fs = require('fs');
const path = require('path');

const OA_KEY   = process.env.OPENAI_API_KEY;
const OA_MODEL = process.env.OPENAI_REALTIME_MODEL || 'gpt-4o-realtime-preview';
const OA_VOICE = process.env.OPENAI_VOICE || 'verse';
const OA_URL   = `wss://api.openai.com/v1/realtime?model=${encodeURIComponent(OA_MODEL)}`;

const HARD_TIMEOUT_MS = 15000;
const LOG_PREFIX = '[Smoke]';

if (!OA_KEY) {
  console.error(`${LOG_PREFIX}[FATAL] OPENAI_API_KEY is not set.`);
  process.exit(1);
}

// --- WAV header for PCM16 mono 24kHz ---
function wavHeader(byteLength, sampleRate = 24000, channels = 1, bitsPerSample = 16) {
  const blockAlign = channels * bitsPerSample / 8;
  const byteRate   = sampleRate * blockAlign;
  const b = Buffer.alloc(44);
  b.write('RIFF', 0);
  b.writeUInt32LE(36 + byteLength, 4);
  b.write('WAVE', 8);
  b.write('fmt ', 12);
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(channels, 22);
  b.writeUInt32LE(sampleRate, 24);
  b.writeUInt32LE(byteRate, 28);
  b.writeUInt16LE(blockAlign, 32);
  b.writeUInt16LE(bitsPerSample, 34);
  b.write('data', 36);
  b.writeUInt32LE(byteLength, 40);
  return b;
}
function writeWavFromPcm(pcm, filename = 'ping.wav') {
  const wav = Buffer.concat([wavHeader(pcm.length, 24000, 1, 16), pcm]);
  const out = path.join(process.cwd(), filename);
  fs.writeFileSync(out, wav);
  console.log(`${LOG_PREFIX} Wrote ${out} (bytes=${wav.length})`);
}

const ws = new WS(OA_URL, {
  headers: {
    Authorization: `Bearer ${OA_KEY}`,
    'OpenAI-Beta': 'realtime=v1'
  }
});

let chunks = [];
let gotAnyAudio = false;
let accumText = '';
let finished = false;

function finalizeAndClose(reason) {
  if (finished) return;
  finished = true;
  if (gotAnyAudio && chunks.length) {
    writeWavFromPcm(Buffer.concat(chunks), 'ping.wav');
  } else if (accumText) {
    console.log(`${LOG_PREFIX} Text:`, accumText);
  } else {
    console.warn(`${LOG_PREFIX} No audio or text received (${reason}).`);
  }
  try { ws.close(1000, reason || 'done'); } catch {}
}

function armTimeout() {
  setTimeout(() => finalizeAndClose('timeout'), HARD_TIMEOUT_MS);
}

ws.on('open', () => {
  console.log(`${LOG_PREFIX} Connected. Sending session.update and response.create…`);
  ws.send(JSON.stringify({
    type: 'session.update',
    session: {
      input_audio_format:  'pcm16',
      output_audio_format: 'pcm16',
      voice: OA_VOICE,
      modalities: ['audio', 'text'],
    }
  }));
  ws.send(JSON.stringify({
    type: 'response.create',
    response: {
      modalities: ['audio', 'text'],
      instructions: 'Say: "ping ok". Keep it very short.'
    }
  }));
  armTimeout();
});

ws.on('message', (data, isBinary) => {
  if (isBinary) {
    chunks.push(Buffer.from(data));
    gotAnyAudio = true;
    console.log(`${LOG_PREFIX} EVT(binary) +${data.length}B`);
    return;
  }
  let obj;
  try { obj = JSON.parse(data.toString()); } catch {
    console.log(`${LOG_PREFIX} EVT(text, unparsable)`, String(data).slice(0, 160));
    return;
  }
  const t = obj.type || '';
  const brief = JSON.stringify(obj).slice(0, 180);
  console.log(`${LOG_PREFIX} EVT ${t} :: ${brief}`);

  if ((t === 'response.audio.delta' || t === 'response.output_audio.delta') && obj.delta) {
    try {
      const pcm = Buffer.from(obj.delta, 'base64');
      if (pcm.length) { chunks.push(pcm); gotAnyAudio = true; }
    } catch {}
  }

  if ((t === 'response.audio_transcript.delta' || t === 'response.text.delta' || t === 'response.output_text.delta') && obj.delta) {
    accumText += obj.delta;
  }

  if (t === 'response.done' || t === 'response.completed') {
    finalizeAndClose('completed');
  }

  if (t === 'error') {
    console.error(`${LOG_PREFIX}[ERROR]`, JSON.stringify(obj, null, 2));
  }
});

ws.on('close', () => console.log(`${LOG_PREFIX} Closed.`));
ws.on('error', (e) => console.error(`${LOG_PREFIX}[ERROR]`, e && e.message ? e.message : e));
