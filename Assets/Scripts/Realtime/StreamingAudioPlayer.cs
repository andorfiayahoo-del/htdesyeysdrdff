
using System;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Simple streaming audio player that accepts PCM16 frames (mono or interleaved)
/// from an external source (e.g., a realtime gateway), resamples to the
/// Unity output sample rate, and plays them through an AudioSource.
///
/// Exposes the API expected by your other scripts:
///   - int OutputSampleRate { get; }
///   - int AssumedSourceRate { get; set; }  (default 24000)
///   - float CapacitySeconds { get; set; }  (default 8)
///   - float BufferFill01 { get; }          (0..1 ring buffer fill)
///   - void Flush()
///   - void EnqueuePcm16Frame(short[] pcm, int sampleRate, int channels)
///   - void EnqueuePcm16Frame(byte[] pcmBytes, int sampleRate, int channels)
///   - void EnqueuePcm16Frame(short[] pcm, int sampleRate) // mono by default
///   - void EnqueuePcm16Frame(byte[] pcmBytes, int sampleRate) // mono by default
/// </summary>
[RequireComponent(typeof(AudioSource))]
public class StreamingAudioPlayer : MonoBehaviour
{
    public int OutputSampleRate { get; private set; }
    /// <summary>Used if the source sample rate is not provided externally.</summary>
    public int AssumedSourceRate { get; set; } = 24000;

    /// <summary>Target capacity in seconds; only applied on Awake/Start.</summary>
    public float CapacitySeconds { get; set; } = 8f;

    /// <summary>Approximate buffer fill [0..1].</summary>
    public float BufferFill01
    {
        get
        {
            lock (_lock)
            {
                return _capacitySamples > 0 ? Mathf.Clamp01((float)_count / (float)_capacitySamples) : 0f;
            }
        }
    }

    private AudioSource _source;
    private System.Object _lock = new System.Object();

    // We'll store MONO samples in the ring at OutputSampleRate.
    private float[] _ring;
    private int _capacitySamples;
    private int _read;   // read index
    private int _write;  // write index
    private int _count;  // number of valid samples in ring

    private void Awake()
    {
        OutputSampleRate = AudioSettings.outputSampleRate > 0 ? AudioSettings.outputSampleRate : 48000;
        _capacitySamples = Mathf.Max(1024, (int)(CapacitySeconds * OutputSampleRate));

        _ring = new float[_capacitySamples];
        _read = 0;
        _write = 0;
        _count = 0;

        _source = GetComponent<AudioSource>();
        if (_source == null) _source = gameObject.AddComponent<AudioSource>();
        _source.playOnAwake = true;
        _source.loop = true; // stream forever
        _source.spatialBlend = 0f; // 2D audio
        _source.clip = AudioClip.Create("StreamingAudioPlayerClip", 1, 1, OutputSampleRate, true, OnAudioFilterReadClip);
        _source.Play();

        Debug.Log($"[Player] Awake. OutputRate={OutputSampleRate}Hz  Capacity={CapacitySeconds:0.#}s");
    }

    /// <summary>
    /// Unity's pull-based callback for AudioClip. We ignore this and fill in OnAudioFilterRead instead.
    /// We still must create a streaming clip to keep the source active on all platforms.
    /// </summary>
    private void OnAudioFilterReadClip(float[] data)
    {
        // No-op; we stream in OnAudioFilterRead.
        for (int i = 0; i < data.Length; i++) data[i] = 0f;
    }

    /// <summary>
    /// This gets called on the audio thread. We must be fast and lock briefly.
    /// </summary>
    private void OnAudioFilterRead(float[] data, int channels)
    {
        if (channels <= 0) channels = 1;

        int frames = data.Length / channels;
        int wrote = 0;

        lock (_lock)
        {
            for (int f = 0; f < frames; f++)
            {
                float sample = 0f;
                if (_count > 0)
                {
                    sample = _ring[_read];
                    _read = (_read + 1) % _capacitySamples;
                    _count--;
                }
                // write to all channels (mono -> stereo/whatever)
                for (int c = 0; c < channels; c++)
                {
                    data[wrote++] = sample;
                }
            }
        }
        // If underrun, remaining samples already zero due to default float[] init or previous loop.
    }

    public void Flush()
    {
        lock (_lock)
        {
            _read = 0;
            _write = 0;
            _count = 0;
            Array.Clear(_ring, 0, _ring.Length);
        }
        Debug.Log("[Player] Flushed.");
    }

    // --------------------------- Enqueue API (3-arg overloads) ---------------------------

    public void EnqueuePcm16Frame(byte[] pcmBytes, int sampleRate, int channels)
    {
        if (pcmBytes == null || pcmBytes.Length == 0) return;
        int sampleCount = pcmBytes.Length / 2;
        short[] pcm = new short[sampleCount];
        Buffer.BlockCopy(pcmBytes, 0, pcm, 0, pcmBytes.Length);
        EnqueuePcm16Frame(pcm, sampleRate, channels);
    }

    public void EnqueuePcm16Frame(short[] pcm, int sampleRate, int channels)
    {
        if (pcm == null || pcm.Length == 0) return;
        if (channels <= 0) channels = 1;
        if (sampleRate <= 0) sampleRate = AssumedSourceRate;

        // Convert interleaved PCM16 to mono float[] at source rate
        int srcFrames = pcm.Length / channels;
        float[] monoSrc = _tempFloatBuffer;
        if (monoSrc == null || monoSrc.Length < srcFrames)
        {
            monoSrc = new float[srcFrames];
            _tempFloatBuffer = monoSrc;
        }

        if (channels == 1)
        {
            // Fast path: mono
            for (int i = 0; i < srcFrames; i++)
            {
                monoSrc[i] = pcm[i] / 32768f;
            }
        }
        else
        {
            // Average channels to mono
            for (int f = 0; f < srcFrames; f++)
            {
                int baseIdx = f * channels;
                int acc = 0;
                for (int c = 0; c < channels; c++) acc += pcm[baseIdx + c];
                monoSrc[f] = (acc / (float)channels) / 32768f;
            }
        }

        // Resample to OutputSampleRate if needed
        if (sampleRate == OutputSampleRate)
        {
            WriteToRing(monoSrc, srcFrames);
        }
        else
        {
            int dstFrames = Mathf.CeilToInt(srcFrames * (OutputSampleRate / (float)sampleRate));
            float[] resampled = _tempResampleBuffer;
            if (resampled == null || resampled.Length < dstFrames)
            {
                resampled = new float[dstFrames];
                _tempResampleBuffer = resampled;
            }
            LinearResample(monoSrc, srcFrames, sampleRate, resampled, dstFrames, OutputSampleRate);
            WriteToRing(resampled, dstFrames);
        }
    }

    // --------------------------- Convenience overloads (2 args) ---------------------------

    public void EnqueuePcm16Frame(byte[] pcmBytes, int sampleRate)
    {
        EnqueuePcm16Frame(pcmBytes, sampleRate, 1);
    }

    public void EnqueuePcm16Frame(short[] pcm, int sampleRate)
    {
        EnqueuePcm16Frame(pcm, sampleRate, 1);
    }

    // --------------------------- Internals ---------------------------

    private float[] _tempFloatBuffer;
    private float[] _tempResampleBuffer;

    private void WriteToRing(float[] src, int count)
    {
        lock (_lock)
        {
            int idx = 0;
            while (idx < count)
            {
                if (_count >= _capacitySamples)
                {
                    // overwrite oldest (drop oldest samples)
                    _read = (_read + 1) % _capacitySamples;
                    _count--;
                }

                int spaceToEnd = _capacitySamples - _write;
                int toCopy = Mathf.Min(spaceToEnd, count - idx);

                Array.Copy(src, idx, _ring, _write, toCopy);

                _write = (_write + toCopy) % _capacitySamples;
                _count += toCopy;
                idx += toCopy;
            }
        }
    }

    /// <summary>
    /// Simple linear resampler (mono).
    /// </summary>
    private static void LinearResample(float[] src, int srcFrames, int srcRate, float[] dst, int dstFrames, int dstRate)
    {
        if (srcFrames <= 1 || dstFrames <= 0)
        {
            if (dstFrames > 0) Array.Clear(dst, 0, dstFrames);
            return;
        }

        double ratio = (double)srcRate / (double)dstRate;
        for (int i = 0; i < dstFrames; i++)
        {
            double srcPos = i * ratio;
            int i0 = (int)Math.Floor(srcPos);
            int i1 = Math.Min(i0 + 1, srcFrames - 1);
            float t = (float)(srcPos - i0);
            float s0 = src[i0];
            float s1 = src[i1];
            dst[i] = s0 + (s1 - s0) * t;
        }
    }
}
