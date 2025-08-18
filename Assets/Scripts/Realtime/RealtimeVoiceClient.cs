// Assets/Scripts/Realtime/RealtimeVoiceClient.cs
// Minimal drop-in client that (1) sends correct session.update with string formats
// and (2) avoids empty commits by only committing after >= MinCommitMs audio appended.
// Uses WebSocketSharp (commonly used in Unity). If you use another WS lib, adapt the calls.
// This script keeps the public API / log style similar to your previous logs.

#nullable enable
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using UnityEngine;
#if !UNITY_WEBGL || UNITY_EDITOR
using WebSocketSharp;
#endif

[DefaultExecutionOrder(-50)]
public class RealtimeVoiceClient : MonoBehaviour
{
    [Header("Gateway")]
    public string Url = "ws://127.0.0.1:8765";
    public bool AutoConnect = true;

    [Header("Mic")]
    public string MicDeviceName = ""; // empty = default
    public int MicSampleRate = 44100;
    public int MicChannels = 1;
    public int MicChunkMs = 40; // chunk size to append
    public float GainDb = 34f;

    [Header("VAD / Commit")]
    public bool AutoCommitWhileSpeaking = true;
    public float CommitEverySeconds = 1.20f;
    public int MinCommitMs = 120; // must have >= N ms since last commit
    public float VadStartDb = -94.4f; // filled at runtime after calibration
    public float VadEndDb = -104.4f;  // filled at runtime after calibration
    public float VadCalibrateSeconds = 1.0f;

    [Header("Refs")]
    public StreamingAudioPlayer? OutputPlayer;
    public RealtimeVoiceHUD? HUD;

#if !UNITY_WEBGL || UNITY_EDITOR
    private WebSocket? _ws;
#endif
    private AudioClip? _micClip;
    private int _micReadPos = 0;
    private float _lastCommitAt;
    private bool _speaking = false;
    private bool _gatewayReady = false;
    private int _bytesSinceLastCommit = 0;
    private float _noiseFloorDb = -104.0f;

    private const string TAG = "[Realtime]";

    void Awake()
    {
        Debug.Log($"[Realtime] Awake. Config: url={Url} mic='{(string.IsNullOrEmpty(MicDeviceName) ? "(default)" : MicDeviceName)}' {MicSampleRate}Hz ch={MicChannels}  autoConnect={AutoConnect} bargeIn=True autoCommitWhileSpeaking={AutoCommitWhileSpeaking} commitEvery={CommitEverySeconds:0.00}s");
        if (!OutputPlayer)
        {
            OutputPlayer = FindObjectOfType<StreamingAudioPlayer>();
        }
        if (!HUD)
        {
            HUD = FindObjectOfType<RealtimeVoiceHUD>();
        }
        if (HUD) Debug.Log("[HUD] Awake. Auto-wired refs? client=True player=True");
        if (OutputPlayer) Debug.Log($"[Player] Awake. OutputRate={OutputPlayer.OutputSampleRate}Hz  Capacity={OutputPlayer.CapacitySeconds}s");

        if (AutoConnect)
        {
            StartCoroutine(BootstrapRoutine());
        }
    }

    IEnumerator BootstrapRoutine()
    {
        yield return StartCoroutine(WaitForMicStart());
        yield return StartCoroutine(CalibrateVAD());
        yield return StartCoroutine(ConnectGateway());
        SendSessionUpdate();
        StartCoroutine(MicLoop());
#if !UNITY_WEBGL || UNITY_EDITOR
        StartCoroutine(ReceiveLoop());
#endif
    }

    IEnumerator WaitForMicStart()
    {
        // Start mic
        int minFreq, maxFreq;
        Microphone.GetDeviceCaps(MicDeviceName, out minFreq, out maxFreq);
        int rate = MicSampleRate;
        if (maxFreq > 0 && rate > maxFreq) rate = maxFreq;
        _micClip = Microphone.Start(MicDeviceName, true, 10, rate); // 10s rolling buffer
        while (Microphone.GetPosition(MicDeviceName) <= 0) yield return null;
        Debug.Log($"[Realtime] Mic started @ {rate}Hz device='{(string.IsNullOrEmpty(MicDeviceName) ? "(default)" : MicDeviceName)}'. Gain={GainDb:+0;-0;0} dB");
        _micReadPos = 0;
        yield break;
    }

    IEnumerator CalibrateVAD()
    {
        Debug.Log($"[Realtime][VAD] Pre-calibration thresholds Start={VadStartDb:0.0} dB, End={VadEndDb:0.0} dB");
        Debug.Log($"[Realtime][VAD] Calibrating for {VadCalibrateSeconds:0.0}s… stay quiet for a moment.");
        float end = Time.time + VadCalibrateSeconds;
        float minDb = +999f;
        while (Time.time < end)
        {
            float db = MeasureCurrentDb();
            if (db < minDb) minDb = db;
            yield return null;
        }
        _noiseFloorDb = float.IsFinite(minDb) ? minDb : -104.0f;
        VadStartDb = _noiseFloorDb + 10f;
        VadEndDb = _noiseFloorDb + 0f;
        Debug.Log($"[Realtime][VAD] Calibration done. Noise={_noiseFloorDb:0.0} dB  Start={VadStartDb:0.0} dB  End={VadEndDb:0.0} dB  Gain={GainDb:+0;-0;0} dB");
        yield break;
    }

    float MeasureCurrentDb()
    {
        if (_micClip == null) return -120f;
        int micPos = Microphone.GetPosition(MicDeviceName);
        int sampleCount = (int)(MicSampleRate * 0.050f); // 50ms window
        if (sampleCount <= 0) return -120f;
        float[] buf = new float[sampleCount];
        int start = Math.Max(0, micPos - sampleCount);
        _micClip.GetData(buf, start);
        // apply gain
        float gain = Mathf.Pow(10f, GainDb / 20f);
        double sum = 0d;
        for (int i = 0; i < buf.Length; i++)
        {
            float v = buf[i] * (float)gain;
            sum += v * v;
        }
        double rms = Math.Sqrt(sum / Math.Max(1, buf.Length));
        double db = 20.0 * Math.Log10(Math.Max(1e-7, rms));
        return (float)db;
    }

    IEnumerator ConnectGateway()
    {
#if !UNITY_WEBGL || UNITY_EDITOR
        _ws = new WebSocket(Url);
        _ws.WaitTime = TimeSpan.FromSeconds(5);
        _ws.OnOpen += (s, e) =>
        {
            Debug.Log($"{TAG} Connected to gateway.");
            _gatewayReady = true;
        };
        _ws.OnClose += (s, e) =>
        {
            Debug.LogWarning($"{TAG} Disconnected from gateway: {e.Reason}");
            _gatewayReady = false;
        };
        _ws.OnError += (s, e) =>
        {
            Debug.LogError($"{TAG} Error: {e.Message}");
        };
        _ws.OnMessage += (s, e) =>
        {
            if (e.IsBinary)
            {
                // Downstream audio; assume PCM16, mono @ unknown rate. Let player guess/convert.
                if (OutputPlayer != null)
                {
                    OutputPlayer.EnqueuePcm16Frame(e.RawData, OutputPlayer.AssumedSourceRate, 1);
                }
            }
            else
            {
                HandleGatewayText(e.Data);
            }
        };
        _ws.ConnectAsync();
        while (!_gatewayReady) yield return null;
#else
        Debug.LogError($"{TAG} WebSocket not supported on this platform build. Use native transport.");
        yield break;
#endif
    }

    public void SendSessionUpdate()
    {
#if !UNITY_WEBGL || UNITY_EDITOR
        if (_ws == null || !_ws.IsAlive) return;
        // IMPORTANT: force string formats
        var payload = "{\"type\":\"session.update\",\"session\":{\"input_audio_format\":\"pcm16\",\"output_audio_format\":\"pcm16\"}}";
        if (_ws.ReadyState == WebSocketState.Open) _ws.Send(payload); else Debug.LogError("[Realtime] WS not open; dropping payload.");
        Debug.Log($"{TAG} Sent session.update (voice+instructions only; gateway controls formats).");
#endif
    }

    IEnumerator MicLoop()
    {
        float lastMeterAt = 0f;
        float lastAppendAt = 0f;
        _lastCommitAt = Time.time;

        var chunkSamples = (MicSampleRate * MicChunkMs) / 1000;
        float[] tmp = new float[Mathf.Max(1, chunkSamples)];
        var appendHeader = Encoding.UTF8.GetBytes("{\"type\":\"input_audio_buffer.append\"}"); // gateway ignores this marker; data is sent binary next

        while (true)
        {
            // VAD meter print
            if (Time.time - lastMeterAt >= 0.25f)
            {
                float db = MeasureCurrentDb();
                Debug.Log($"[Realtime][VAD] dB={db:0.0}  Start={VadStartDb:0.0}  End={VadEndDb:0.0}  speaking={_speaking}");
                lastMeterAt = Time.time;
            }

#if !UNITY_WEBGL || UNITY_EDITOR
            if (_ws != null && _ws.IsAlive && _micClip != null)
            {
                int micPos = Microphone.GetPosition(MicDeviceName);
                int available = micPos - _micReadPos;
                if (available < 0) available += _micClip.samples; // wrap
                while (available >= tmp.Length)
                {
                    _micClip.GetData(tmp, _micReadPos);
                    _micReadPos = (_micReadPos + tmp.Length) % _micClip.samples;

                    // gain + convert to PCM16
                    short[] s16 = new short[tmp.Length];
                    float gain = Mathf.Pow(10f, GainDb / 20f);
                    for (int i = 0; i < tmp.Length; i++)
                    {
                        float v = Mathf.Clamp(tmp[i] * gain, -1f, 1f);
                        s16[i] = (short)Mathf.RoundToInt(v * 32767f);
                    }
                    byte[] bytes = new byte[s16.Length * 2];
                    Buffer.BlockCopy(s16, 0, bytes, 0, bytes.Length);

                    // Send a small JSON marker then the raw PCM16 as binary frame
                    if (_ws.ReadyState == WebSocketState.Open) _ws.Send(appendHeader); else Debug.LogError("[Realtime] WS not open; dropping audio header.");
                    if (_ws.ReadyState == WebSocketState.Open) _ws.Send(bytes); else Debug.LogError("[Realtime] WS not open; dropping audio bytes.");
                    _bytesSinceLastCommit += bytes.Length;
                    lastAppendAt = Time.time;
                }

                // VAD simple threshold on current meter
                float curDb = MeasureCurrentDb();
                bool speakingNow = curDb >= VadStartDb ? true : (curDb <= VadEndDb ? false : _speaking);
                if (speakingNow != _speaking)
                {
                    if (speakingNow)
                    {
                        Debug.Log($"{TAG} Barge-in (VAD start).");
                        if (OutputPlayer) OutputPlayer.Flush();
                    }
                    _speaking = speakingNow;
                }

                // auto-commit rules
                if (AutoCommitWhileSpeaking && _speaking && (Time.time - _lastCommitAt) >= CommitEverySeconds)
                {
                    Debug.Log($"{TAG} Auto-commit utterance.");
                    TryCommit();
                }

                if (!_speaking && (Time.time - lastAppendAt) > 0.4f && (Time.time - _lastCommitAt) > 0.4f)
                {
                    Debug.Log($"{TAG} Auto-commit utterance (VAD end).");
                    TryCommit();
                }
            }
#endif
            yield return null;
        }
    }

    void TryCommit()
    {
#if !UNITY_WEBGL || UNITY_EDITOR
        if (_ws == null || !_ws.IsAlive) return;
        // Guard: only commit if we sent at least MinCommitMs worth of bytes since last commit
        int minBytes = (int)((MicSampleRate * (MinCommitMs / 1000f)) * MicChannels * 2);
        if (_bytesSinceLastCommit < minBytes)
        {
            Debug.LogError($"{TAG}[UpstreamError] {{\"type\":\"error\",\"event_id\":\"(local)\",\"error\":{{\"type\":\"invalid_request_error\",\"code\":\"input_audio_buffer_commit_empty\",\"message\":\"Guarded: not enough audio to commit yet (have ~{_bytesSinceLastCommit}B, need >= {minBytes}B).\"}}}}");
            return;
        }
        if (_ws.ReadyState == WebSocketState.Open) _ws.Send("{\"type\":\"input_audio_buffer.commit\"}"); else Debug.LogWarning("[Realtime] Commit skipped; WS closed.");
        _bytesSinceLastCommit = 0;
        _lastCommitAt = Time.time;
#endif
    }

    IEnumerator ReceiveLoop()
    {
#if !UNITY_WEBGL || UNITY_EDITOR
        while (_ws != null && _ws.IsAlive)
        {
            // WebSocketSharp invokes callbacks; nothing to do here.
            yield return null;
        }
#else
        yield break;
#endif
    }

    public void HandleGatewayText(string json)
    {
        // Log upstream errors in editor to mirror your logs
        if (json.Contains("\"type\":\"error\"") || json.Contains("\"status\":\"failed\""))
        {
            Debug.LogError($"{TAG}[UpstreamError] {json}");
        }
        else
        {
            Debug.Log($"{TAG} {json}");
        }
    }

    void OnDestroy()
    {
#if !UNITY_WEBGL || UNITY_EDITOR
        try { _ws?.Close(); } catch {}
#endif
        if (!string.IsNullOrEmpty(MicDeviceName) && Microphone.IsRecording(MicDeviceName))
        {
            Microphone.End(MicDeviceName);
        }
    }
}
