#if UNITY_EDITOR
using UnityEditor;
#endif
using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Security.Cryptography;
using UnityEngine;

[Serializable] public class ActionBatch {
    public int version = 1;
    public CreateCSharpAction[] create_csharp;
    public BuildBlueprintAction[] build_blueprint;
    public SpeakText[] speak;                 // optional planner text
    public PlayAudioAction[] play_audio;      // WAV base64 from bridge/gateway TTS
    public LogAction[] log;
}
[Serializable] public class CreateCSharpAction { public string path; public string contents; }
[Serializable] public class BuildBlueprintAction { public string name; public Blueprint blueprint; }
[Serializable] public class LogAction { public string level; public string message; }
[Serializable] public class SpeakText { public string text; public string voice; }
[Serializable] public class PlayAudioAction { public string wav_base64; public float volume = 1f; }

public class VoiceCommandReceiver : MonoBehaviour
{
    [Header("Bridge")]
    [SerializeField] string host = "127.0.0.1";
    [SerializeField] int port = 65436;

    [Header("Save Location (legacy PROTO=1)")]
    [SerializeField] string folder = "Assets/GeneratedScripts";

    [Header("Audio")]
    [SerializeField] string speakerObjectName = "AssistantSpeaker";

    TcpClient _client;
    Thread _listenThread;

    static string T => DateTime.Now.ToString("HH:mm:ss.fff");
    static void L(string msg) => Debug.Log($"[{T}] [Unity] {msg}");
    static void LW(string msg) => Debug.LogWarning($"[{T}] [Unity] {msg}");
    static void LE(string msg) => Debug.LogError($"[{T}] [Unity] {msg}");

    AudioSource _speaker;

    void OnEnable()
    {
        L($"Project: {Application.dataPath}");
        EnsureSpeaker();
#if UNITY_EDITOR
        StartCoroutine(ReconnectLoop());
#else
        StartListeningOnce();
#endif
    }

    void OnDisable()
    {
        try { _client?.Close(); } catch { }
        try { if (_listenThread != null && _listenThread.IsAlive) _listenThread.Join(200); } catch { }
        L("Receiver disabled.");
    }

    void EnsureSpeaker()
    {
        var go = GameObject.Find(speakerObjectName);
        if (go == null)
        {
            go = new GameObject(speakerObjectName);
            go.hideFlags = HideFlags.DontSave;
        }
        _speaker = go.GetComponent<AudioSource>();
        if (_speaker == null) _speaker = go.AddComponent<AudioSource>();
        _speaker.playOnAwake = false;
        _speaker.spatialBlend = 0f;
        _speaker.loop = false;
        _speaker.volume = 1f;
    }

#if UNITY_EDITOR
    System.Collections.IEnumerator ReconnectLoop()
    {
        while (isActiveAndEnabled)
        {
            while (EditorApplication.isCompiling || EditorApplication.isUpdating || !EditorIdleGate.IsEditorIdle)
                yield return null;

            StartListeningOnce();
            while (_listenThread != null && _listenThread.IsAlive)
                yield return null;
            yield return null;
        }
    }
#endif

    void StartListeningOnce()
    {
        _listenThread = new Thread(ListenOnce)
        {
            IsBackground = true,
            Name = "VC_ListenOnce"
        };
        _listenThread.Start();
    }

    void ListenOnce()
    {
        try
        {
            _client = new TcpClient { NoDelay = true };
            _client.Connect(host, port);
            L("Connected to Python.");

            using var stream = _client.GetStream();

            string protoStr = ReadHeaderValue(stream, "PROTO"); if (protoStr == null) return;
            int proto = 1; int.TryParse(protoStr, out proto);
            L($"Header PROTO = {proto}");

            string seqStr = ReadHeaderValue(stream, "SEQ"); if (seqStr == null) return;
            int seq = 0; int.TryParse(seqStr, out seq);
            L($"Header SEQ = {seq}");

            string rawName = ReadHeaderValue(stream, "NAME"); if (rawName == null) return;
            string className = SanitizeClass(rawName.Trim());
            L($"Header NAME = {className}");

            string lenStr = ReadHeaderValue(stream, "LEN"); if (lenStr == null) return;
            int payloadLen = 0; int.TryParse(lenStr, out payloadLen);
            L($"Header LEN = {payloadLen}");

            string sha1 = ReadHeaderValue(stream, "SHA1"); if (sha1 == null) return;

            if (payloadLen <= 0)
            {
                LE($"Invalid/zero payload length for '{className}'. Skipping.");
                WriteASCII(stream, "RECV\n");
                return;
            }

            byte[] buf = new byte[payloadLen];
            ReadExact(stream, buf, 0, payloadLen);
            string payload = Encoding.UTF8.GetString(buf);

            // optional integrity check
            try {
                using var sh = SHA1.Create();
                var gotSha = BitConverter.ToString(sh.ComputeHash(Encoding.UTF8.GetBytes(payload))).Replace("-", "").ToLowerInvariant();
                if (!string.Equals(gotSha, sha1.Trim().ToLowerInvariant()))
                    LW($"SHA1 mismatch (expected={sha1} got={gotSha})");
            } catch (Exception ex) { LW($"SHA1 verify error: {ex.Message}"); }

            WriteASCII(stream, "RECV\n"); // ack ASAP

            if (proto <= 1)
            {
                SaveLegacyScript(className, payload, seq, sha1, payloadLen);
            }
            else if (proto == 2)
            {
                HandleActionBatch(payload);
            }
            else
            {
                LE($"Unknown PROTO {proto}. Ignoring payload.");
            }
        }
        catch (Exception ex)
        {
            LE($"Listener IO error: {ex.Message}");
        }
        finally
        {
            try { _client?.Close(); } catch { }
            L("Listener stopped.");
        }
    }

    void HandleActionBatch(string json)
    {
        ActionBatch batch = null;
        try { batch = JsonUtility.FromJson<ActionBatch>(json); }
        catch (Exception ex) { LE($"Failed to parse ActionBatch: {ex.Message}"); return; }
        if (batch == null) { LE("ActionBatch null."); return; }
        if (batch.version != 1) LW($"ActionBatch version={batch.version} (expected 1)");

        if (batch.create_csharp != null)
        {
            foreach (var a in batch.create_csharp)
            {
                if (string.IsNullOrEmpty(a.path) || string.IsNullOrEmpty(a.contents)) { LW("create_csharp missing path/contents"); continue; }
                SaveScriptToPath(a.path, a.contents);
            }
        }

        if (batch.build_blueprint != null)
        {
            foreach (var b in batch.build_blueprint)
            {
                if (b == null || b.blueprint == null) { LW("build_blueprint missing data"); continue; }
                string rootName = string.IsNullOrEmpty(b.name) ? (b.blueprint.@class ?? "GeneratedRoot") : b.name;
                var root = BlueprintBuilder.Build(rootName, b.blueprint);
                if (root != null) L($"Built blueprint '{root.name}' with {root.transform.childCount} parts.");
            }
        }

        if (batch.play_audio != null && batch.play_audio.Length > 0)
        {
            foreach (var a in batch.play_audio)
            {
                PlayAudioFromBase64(a.wav_base64, Mathf.Clamp01(a.volume));
            }
        }

        if (batch.log != null)
        {
            foreach (var lg in batch.log)
            {
                var lvl = (lg.level ?? "info").ToLowerInvariant();
                if (lvl == "warn") LW(lg.message ?? "");
                else if (lvl == "error") LE(lg.message ?? "");
                else L(lg.message ?? "");
            }
        }

#if UNITY_EDITOR
        EditorMainThread.Enqueue(() =>
        {
            EditorIdleGate.NotifyImportRequested();
            AssetDatabase.Refresh(ImportAssetOptions.ForceUpdate);
            EditorIdleGate.NotifyImportFinished();
        });
#endif
    }

    void PlayAudioFromBase64(string b64, float volume)
    {
        if (string.IsNullOrEmpty(b64)) return;
        try
        {
            var bytes = Convert.FromBase64String(b64);
            var clip = WavUtility.ToAudioClip(bytes, "AssistantLine");
            if (clip == null) { LW("WAV decode failed."); return; }
            EnsureSpeaker();
            _speaker.volume = volume;
            _speaker.Stop();
            _speaker.clip = clip;
            _speaker.Play();
        }
        catch (Exception ex) { LE($"play_audio error: {ex.Message}"); }
    }

    void SaveLegacyScript(string className, string source, int seq, string sha1, int bytes)
    {
        try
        {
            string folderAbs;
            if (folder == "Assets") folderAbs = Application.dataPath;
            else if (folder.StartsWith("Assets/")) folderAbs = Path.Combine(Application.dataPath, folder.Substring("Assets/".Length));
            else folderAbs = Path.GetFullPath(folder);

            Directory.CreateDirectory(folderAbs);
            string fileAbs = Path.Combine(folderAbs, $"{className}.cs");
            File.WriteAllText(fileAbs, source, new UTF8Encoding(false));
#if UNITY_EDITOR
            EditorIdleGate.AnnounceIncomingScript();
#endif
            L($"CREATED SEQ={seq} class={className} bytes={bytes} sha1={sha1} → {ToAssetPath(fileAbs)}");
#if UNITY_EDITOR
            EditorMainThread.Enqueue(() =>
            {
                try {
                    string assetPath = ToAssetPath(fileAbs);
                    EditorIdleGate.NotifyImportRequested();
                    AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceUpdate);
                    AssetDatabase.SaveAssets();
                } catch (Exception ex) { LE($"Import error: {ex.Message}"); }
                finally { EditorIdleGate.NotifyImportFinished(); }
            });
#endif
        }
        catch (Exception ex) { LE($"Error saving legacy script: {ex.Message}"); }
    }

    void SaveScriptToPath(string assetPath, string contents)
    {
        try
        {
            string fileAbs = assetPath.Replace("\\","/");
            if (assetPath.StartsWith("Assets/"))
                fileAbs = Path.Combine(Application.dataPath, assetPath.Substring("Assets/".Length)).Replace("\\","/");
            else if (!Path.IsPathRooted(assetPath))
                fileAbs = Path.Combine(Application.dataPath, assetPath).Replace("\\","/");

            Directory.CreateDirectory(Path.GetDirectoryName(fileAbs));
            File.WriteAllText(fileAbs, contents, new UTF8Encoding(false));
            L($"create_csharp wrote {assetPath} ({contents.Length} chars)");

#if UNITY_EDITOR
            EditorMainThread.Enqueue(() =>
            {
                try {
                    string ap = ToAssetPath(fileAbs);
                    EditorIdleGate.NotifyImportRequested();
                    AssetDatabase.ImportAsset(ap, ImportAssetOptions.ForceUpdate);
                    AssetDatabase.SaveAssets();
                } catch (Exception ex) { LE($"Import error: {ex.Message}"); }
                finally { EditorIdleGate.NotifyImportFinished(); }
            });
#endif
        }
        catch (Exception ex) { LE($"create_csharp error: {ex.Message}"); }
    }

    static string SanitizeClass(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return "GeneratedClass";
        var sb = new StringBuilder(raw.Length);
        foreach (char c in raw) sb.Append(char.IsLetterOrDigit(c) ? c : '_');
        if (sb.Length == 0 || (!char.IsLetter(sb[0]) && sb[0] != '_')) sb.Insert(0, 'C');
        return sb.ToString();
    }

    static string ToAssetPath(string absolutePath)
    {
        string dataRoot = Application.dataPath.Replace("\\", "/");
        string norm = absolutePath.Replace("\\", "/");
        if (norm.StartsWith(dataRoot)) return "Assets" + norm.Substring(dataRoot.Length);
        return absolutePath;
    }

    static string ReadHeaderValue(NetworkStream stream, string key)
    {
        string line = ReadLine(stream);
        if (line == null) return null;
        string t = line.Trim();
        if (t.Length == 0) return "";

        if (t.Equals(key, StringComparison.OrdinalIgnoreCase))
            return ReadLine(stream)?.Trim();

        if (t.StartsWith(key, StringComparison.OrdinalIgnoreCase))
        {
            string rest = t.Substring(key.Length).TrimStart();
            if (rest.StartsWith(":")) rest = rest.Substring(1).TrimStart();
            else if (rest.StartsWith("=")) rest = rest.Substring(1).TrimStart();
            return rest;
        }
        return t;
    }

    static string ReadLine(NetworkStream s)
    {
        var sb = new StringBuilder(64);
        int b;
        while ((b = s.ReadByte()) != -1)
        {
            if (b == (int)'\n') break;
            if (b != (int)'\r') sb.Append((char)b); // Correct: Append
        }
        return b == -1 && sb.Length == 0 ? null : sb.ToString();
    }

    static void ReadExact(NetworkStream s, byte[] buf, int off, int len)
    {
        int got = 0;
        while (got < len)
        {
            int n = s.Read(buf, off + got, len - got);
            if (n <= 0) throw new IOException("socket closed");
            got += n;
        }
    }

    static void WriteASCII(NetworkStream s, string text)
    {
        var bytes = Encoding.ASCII.GetBytes(text);
        s.Write(bytes, 0, bytes.Length);
        s.Flush();
    }
}
