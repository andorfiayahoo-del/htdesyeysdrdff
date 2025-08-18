// RealtimeTextDeltaDebugger.cs
// Minimal, read-only client that connects to the local gateway and logs
// {"type":"text.delta","text":"..."} messages. Does not send audio or interfere
// with your main RealtimeVoiceClient. Safe to remove anytime.

using System;
using System.Collections;
using System.Text;
using UnityEngine;
using WebSocketSharp;   // Install "websocket-sharp" (dll) or use your WS wrapper

public class RealtimeTextDeltaDebugger : MonoBehaviour
{
    [Header("Gateway")]
    public string host = "ws://127.0.0.1:8765";

    private WebSocket ws;

    void OnEnable()
    {
        try
        {
            ws = new WebSocket(host);
            ws.OnOpen += (_, __) => Debug.Log("[TextDelta] Connected.");
            ws.OnError += (_, e) => Debug.LogError("[TextDelta] WS error: " + e.Message);
            ws.OnClose += (_, e) => Debug.Log("[TextDelta] WS closed: " + e.Code + " " + e.Reason);

            ws.OnMessage += (_, m) =>
            {
                if (m.IsText)
                {
                    try
                    {
                        var json = m.Data;
                        // super tiny filter to avoid bringing in a JSON lib:
                        if (json.Contains("\"type\":\"text.delta\""))
                        {
                            // brittle-but-fine: pull the 'text' field
                            var idx = json.IndexOf("\"text\"");
                            if (idx >= 0)
                            {
                                var s = json.IndexOf(':', idx) + 1;
                                if (s > 0)
                                {
                                    var trimmed = json.Substring(s).TrimStart();
                                    // strip quotes and trailing } (very naive)
                                    if (trimmed.StartsWith("\"")) trimmed = trimmed.Substring(1);
                                    int end = trimmed.IndexOf('"');
                                    if (end > 0)
                                    {
                                        var delta = trimmed.Substring(0, end).Replace("\\n", "\n");
                                        Debug.Log("[Realtime] TEXT Δ: " + delta);
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                }
            };

            ws.ConnectAsync();
        }
        catch (Exception ex)
        {
            Debug.LogError("[TextDelta] Failed to connect: " + ex.Message);
        }
    }

    void OnDisable()
    {
        try { ws?.CloseAsync(); } catch { }
        ws = null;
    }
}
