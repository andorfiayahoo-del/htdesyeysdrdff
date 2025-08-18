// server.js (ESM)
import { WebSocketServer, WebSocket } from 'ws';
import http from 'http';

const OPENAI_URL =
  'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17';

const PORT_WS = 8765;
const PORT_HEALTH = 8766;

const wssUnity = new WebSocketServer({ port: PORT_WS });
http.createServer((_, res) => { res.writeHead(200); res.end('ok'); }).listen(PORT_HEALTH);

wssUnity.on('connection', (unity) => {
  const openai = new WebSocket(OPENAI_URL, {
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'OpenAI-Beta': 'realtime=v1',
    },
  });

  let openaiReady = false;
  let bytesSinceLastCommit = 0;

  // ~120 ms @ 44.1 kHz, mono, PCM16 (2 bytes/sample)
  const minCommitBytes = Math.ceil(0.12 * 44100) * 2;

  openai.once('open', () => {
    openaiReady = true;

    // IMPORTANT: use server_vad or semantic_vad (not "none")
    openai.send(JSON.stringify({
      type: 'session.update',
      session: {
        input_audio_format:  { format: 'pcm16', sample_rate: 44100, channels: 1 },
        // Match your Unity StreamingAudioPlayer (48 kHz) to avoid resampling surprises
        output_audio_format: { format: 'pcm16', sample_rate: 48000, channels: 1 },
        voice: 'verse',
        turn_detection: { type: 'server_vad', silence_duration_ms: 500, prefix_padding_ms: 200 }
      }
    }));
  });

  // Unity -> OpenAI
  unity.on('message', (data, isBinary) => {
    if (!openaiReady) return;

    if (isBinary) {
      // raw PCM16 mono 44.1k from Unity
      bytesSinceLastCommit += data.length;
      openai.send(JSON.stringify({
        type: 'input_audio_buffer.append',
        audio: data.toString('base64')
      }));
      return;
    }

    let msg;
    try { msg = JSON.parse(data.toString()); } catch { return; }

    if (msg.type === 'input_audio_buffer.commit') {
      if (bytesSinceLastCommit >= minCommitBytes) {
        openai.send(JSON.stringify({ type: 'input_audio_buffer.commit' }));
        bytesSinceLastCommit = 0;
      } else {
        // Too little audio; skip to avoid "buffer too small" error
      }
      return;
    }

    if (msg.type === 'response.create') {
      // DO NOT send "response.audio" (invalid). Rely on session voice/format.
      openai.send(JSON.stringify({
        type: 'response.create',
        response: { modalities: ['audio'] } // ask for audio output
      }));
      return;
    }
  });

  // OpenAI -> Unity
  openai.on('message', (raw) => {
    let evt;
    try { evt = JSON.parse(raw.toString()); } catch { return; }

    switch (evt.type) {
      case 'response.output_audio.delta': {
        const chunk = Buffer.from(evt.delta, 'base64');
        // Forward PCM16 frames to Unity as binary
        unity.send(chunk, { binary: true });
        break;
      }
      case 'error':
        console.error('[Gateway] OpenAI error:', evt);
        break;
      default:
        // ignore non-audio events
        break;
    }
  });

  unity.once('close', () => openai.close());
  openai.once('close', () => unity.close());
});
