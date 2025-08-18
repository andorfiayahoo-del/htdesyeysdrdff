using UnityEngine;
using System;
using System.IO;
using System.Text;

public static class WavUtility
{
    // bytes -> AudioClip (PCM16)
    public static AudioClip ToAudioClip(byte[] wavData, string name = "wav")
    {
        if (wavData == null || wavData.Length < 44) return null;
        using var ms = new MemoryStream(wavData);
        using var br = new BinaryReader(ms);

        string riff = new string(br.ReadChars(4));
        if (riff != "RIFF") return null;
        int chunkSize = br.ReadInt32();
        string wave = new string(br.ReadChars(4));
        if (wave != "WAVE") return null;

        string fmt = new string(br.ReadChars(4));
        if (fmt != "fmt ") return null;
        int subchunk1Size = br.ReadInt32();
        short audioFormat = br.ReadInt16();
        short channels = br.ReadInt16();
        int sampleRate = br.ReadInt32();
        int byteRate = br.ReadInt32();
        short blockAlign = br.ReadInt16();
        short bitsPerSample = br.ReadInt16();

        if (subchunk1Size > 16)
            br.ReadBytes(subchunk1Size - 16);

        string dataID = new string(br.ReadChars(4));
        int dataSize = br.ReadInt32();
        while (dataID != "data")
        {
            br.ReadBytes(dataSize);
            if (br.BaseStream.Position + 8 > br.BaseStream.Length) return null;
            dataID = new string(br.ReadChars(4));
            dataSize = br.ReadInt32();
        }

        if (audioFormat != 1 || bitsPerSample != 16)
        {
            Debug.LogError($"WavUtility: Only PCM 16-bit supported (got format={audioFormat}, bps={bitsPerSample})");
            return null;
        }

        int sampleCount = dataSize / (bitsPerSample / 8);
        int frameCount = sampleCount / channels;

        float[] samples = new float[frameCount * channels];
        for (int i = 0; i < frameCount * channels; i++)
        {
            short s = br.ReadInt16();
            samples[i] = Mathf.Clamp(s / 32768f, -1f, 1f);
        }

        var clip = AudioClip.Create(name, frameCount, channels, Mathf.Max(sampleRate, 8000), false);
        clip.SetData(samples, 0);
        return clip;
    }

    // AudioClip -> bytes (PCM16 WAV)
    public static byte[] FromAudioClip(AudioClip clip)
    {
        if (clip == null)
            throw new ArgumentNullException("clip");

        float[] samples = new float[clip.samples * clip.channels];
        clip.GetData(samples, 0);

        return ConvertToWav(samples, clip.channels, clip.frequency);
    }

    private static byte[] ConvertToWav(float[] samples, int channels, int sampleRate)
    {
        using var stream = new MemoryStream();

        int byteRate = sampleRate * channels * 2;
        int subchunk2Size = samples.Length * 2;
        int chunkSize = 36 + subchunk2Size;

        void WriteString(string s) => stream.Write(Encoding.ASCII.GetBytes(s), 0, s.Length);
        void WriteInt(int i) => stream.Write(BitConverter.GetBytes(i), 0, 4);
        void WriteShort(short s) => stream.Write(BitConverter.GetBytes(s), 0, 2);

        WriteString("RIFF");
        WriteInt(chunkSize);
        WriteString("WAVE");
        WriteString("fmt ");
        WriteInt(16);
        WriteShort(1);
        WriteShort((short)channels);
        WriteInt(sampleRate);
        WriteInt(byteRate);
        WriteShort((short)(channels * 2));
        WriteShort(16);
        WriteString("data");
        WriteInt(subchunk2Size);

        foreach (var sample in samples)
        {
            short intSample = (short)Mathf.Clamp(sample * short.MaxValue, short.MinValue, short.MaxValue);
            WriteShort(intSample);
        }

        return stream.ToArray();
    }
}
