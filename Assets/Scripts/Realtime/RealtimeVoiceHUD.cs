using System;
using System.Reflection;
using UnityEngine;

/// <summary>
/// Editor/runtime HUD that displays connection/mic/VAD/player status
/// without taking a hard compile-time dependency on specific members.
/// It uses reflection to read common member names so it works across
/// slightly different RealtimeVoiceClient / StreamingAudioPlayer APIs.
/// </summary>
public class RealtimeVoiceHUD : MonoBehaviour
{
    [Header("Auto-wire (optional)")]
    public MonoBehaviour client;   // RealtimeVoiceClient or compatible
    public MonoBehaviour player;   // StreamingAudioPlayer or compatible

    [Header("HUD")]
    public bool visible = true;
    public Vector2 margin = new Vector2(10, 10);
    public Vector2 size = new Vector2(380, 150);

    // Styles are created lazily inside OnGUI() to avoid GUI calls outside OnGUI
    GUIStyle _box, _label, _header;
    bool _stylesReady;

    void Awake()
    {
        // DO NOT touch GUI.* here.
        AutoWire();
        Debug.Log($"[HUD] Awake. Auto-wired refs? client={(client!=null)} player={(player!=null)}");
    }

    void AutoWire()
    {
        if (client == null)
        {
            // Try to find any MonoBehaviour named "RealtimeVoiceClient"
            var all = FindObjectsOfType<MonoBehaviour>(true);
            foreach (var mb in all)
            {
                if (mb != null && mb.GetType().Name == "RealtimeVoiceClient")
                {
                    client = mb;
                    break;
                }
            }
        }

        if (player == null)
        {
            // Try to find any MonoBehaviour named "StreamingAudioPlayer"
            var all = FindObjectsOfType<MonoBehaviour>(true);
            foreach (var mb in all)
            {
                if (mb != null && mb.GetType().Name == "StreamingAudioPlayer")
                {
                    player = mb;
                    break;
                }
            }
        }
    }

    void EnsureStyles()
    {
        if (_stylesReady) return;
        // Only legal to access GUI.* inside OnGUI
        _box = new GUIStyle(GUI.skin.box) { alignment = TextAnchor.UpperLeft, fontSize = 12, padding = new RectOffset(8, 8, 6, 6) };
        _label = new GUIStyle(GUI.skin.label) { fontSize = 12 };
        _header = new GUIStyle(GUI.skin.label) { fontSize = 14, fontStyle = FontStyle.Bold };
        _stylesReady = true;
    }

    void OnGUI()
    {
        if (!visible) return;
        EnsureStyles();

        var rect = new Rect(margin.x, margin.y, size.x, size.y);
        GUILayout.BeginArea(rect, GUIContent.none, _box);
        GUILayout.Label("Realtime Voice HUD", _header);

        if (client == null) AutoWire(); // try again if scripts spawned later

        // Read values safely via reflection so we don't depend on exact names
        bool isConnected = GetBool(client, new string[] { "IsConnected", "Connected", "IsReady", "HasConnection" }, false);
        bool isSpeaking  = GetBool(client, new string[] { "IsSpeaking", "Speaking", "VadSpeaking", "VADSpeaking" }, false);
        float lastDb     = GetFloat(client, new string[] { "LastDb", "LastDB", "CurrentDb", "Db" }, float.NaN);
        string micName   = GetString(client, new string[] { "MicDeviceInUse", "MicName", "InputDeviceName" }, "(none)");

        float buffer01   = GetFloat(player, new string[] { "BufferFill01", "BufferFill" }, 0f);
        int outRate      = (int)Mathf.Round(GetFloat(player, new string[] { "OutputSampleRate", "OutputRate", "SampleRate" }, AudioSettings.outputSampleRate));

        GUILayout.Space(4);
        GUILayout.Label($"Connection: {(isConnected ? "Connected" : "Disconnected")}", _label);
        GUILayout.Label($"Mic: {micName}", _label);
        GUILayout.Label($"VAD: {(isSpeaking ? "Speaking" : "Idle")}{(float.IsNaN(lastDb) ? "" : $"  ({lastDb:F1} dB)")}", _label);
        GUILayout.Label($"Player: {(player ? player.GetType().Name : "None")}  |  OutRate={outRate} Hz  |  Buffer={(buffer01*100f):F0}%", _label);

        GUILayout.EndArea();
    }

    // ===== Reflection helpers =====

    bool GetBool(object target, string[] candidateNames, bool fallback)
    {
        var v = GetMemberValue(target, candidateNames);
        if (v == null) return fallback;
        try
        {
            if (v is bool b) return b;
            if (v is int i) return i != 0;
            if (v is float f) return Mathf.Abs(f) > Mathf.Epsilon;
            if (v is double d) return Math.Abs(d) > Double.Epsilon;
            if (bool.TryParse(v.ToString(), out var parsed)) return parsed;
        }
        catch { }
        return fallback;
    }

    float GetFloat(object target, string[] candidateNames, float fallback)
    {
        var v = GetMemberValue(target, candidateNames);
        if (v == null) return fallback;
        try
        {
            if (v is float f) return f;
            if (v is double d) return (float)d;
            if (v is int i) return i;
            if (v is long l) return l;
            if (float.TryParse(v.ToString(), out var parsed)) return parsed;
        }
        catch { }
        return fallback;
    }

    string GetString(object target, string[] candidateNames, string fallback)
    {
        var v = GetMemberValue(target, candidateNames);
        if (v == null) return fallback;
        try
        {
            return v.ToString();
        }
        catch { }
        return fallback;
    }

    object GetMemberValue(object target, string[] candidateNames)
    {
        if (target == null) return null;
        var t = target.GetType();
        foreach (var name in candidateNames)
        {
            // Try property first
            var prop = t.GetProperty(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (prop != null && prop.CanRead)
            {
                try { return prop.GetValue(target, null); } catch { }
            }
            // Then field
            var field = t.GetField(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (field != null)
            {
                try { return field.GetValue(target); } catch { }
            }
        }
        return null;
    }
}
