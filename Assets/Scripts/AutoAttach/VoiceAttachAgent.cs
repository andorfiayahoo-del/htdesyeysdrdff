using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using UnityEngine;

namespace VoiceAutoAttach
{
    /// <summary>
    /// ONE FILE:
    ///  - Runtime: watches Assets/GeneratedScripts, attaches new components during Play (immediately).
    ///  - Editor-only (inside #if UNITY_EDITOR at bottom): mirrors these attachments back to Edit Mode so they persist.
    ///
    /// Place this script OUTSIDE any 'Editor' folder.
    /// </summary>
    [DefaultExecutionOrder(-10000)]
    public class VoiceAttachAgent : MonoBehaviour
    {
        [Header("Watch")]
        [Tooltip("Folder where VoiceCommandReceiver writes scripts.")]
        public string scriptsFolder = "Assets/GeneratedScripts";

        [Tooltip("How often to scan the folder (seconds).")]
        public float scanInterval = 0.75f;

        // File names used to coordinate runtime/editor
        const string StateFileName = "_voice_attach_state.json";   // which cs files we saw + sha1 + class + attached?
        const string CreatedFileName = "_voice_play_created.json";   // what we created/attached while in Play (for persistence)

        [Serializable] class SeenEntry { public string file; public string sha1; public string className; public bool attached; }
        [Serializable] class SeenState { public List<SeenEntry> entries = new(); }

        [Serializable] class CreatedEntry { public string goName; public string className; }
        [Serializable] class CreatedList { public List<CreatedEntry> items = new(); }

        string _scriptsAbs;
        string _stateAbs;
        string _createdAbs;
        SeenState _state;
        CreatedList _created;

        static VoiceAttachAgent _instance;

        string T => DateTime.Now.ToString("HH:mm:ss.fff");
        void L(string msg) => Debug.Log($"[{T}] [VoiceAttach] {msg}");
        void W(string msg) => Debug.LogWarning($"[{T}] [VoiceAttach] {msg}");
        void E(string msg) => Debug.LogError($"[{T}] [VoiceAttach] {msg}");

        // Auto-spawn during Play and survive scene loads
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Bootstrap()
        {
            if (_instance != null) return;
            var go = new GameObject("VoiceAttachAgent(Runtime)");
            DontDestroyOnLoad(go);
            _instance = go.AddComponent<VoiceAttachAgent>();
        }

        void Awake()
        {
            _scriptsAbs = ToAbs(scriptsFolder);
            _stateAbs = Path.Combine(_scriptsAbs, StateFileName);
            _createdAbs = Path.Combine(_scriptsAbs, CreatedFileName);

            _state = LoadJson<SeenState>(_stateAbs) ?? new SeenState();
            _created = LoadJson<CreatedList>(_createdAbs) ?? new CreatedList();

            L($"Agent awake. Watching '{scriptsFolder}'. Abs='{_scriptsAbs}'");
        }

        void OnEnable()
        {
            StopAllCoroutines();
            StartCoroutine(WatchLoop());
        }

        IEnumerator WatchLoop()
        {
            // slight delay to avoid racing right after a reload
            yield return new WaitForSeconds(0.25f);

            for (; ; )
            {
                try { ScanOnce(); }
                catch (Exception ex) { E($"Scan error: {ex.Message}"); }
                yield return new WaitForSeconds(scanInterval);
            }
        }

        void ScanOnce()
        {
            if (!Application.isPlaying) return;

            if (!Directory.Exists(_scriptsAbs))
            {
                // First time projects may not have the folder yet.
                return;
            }

            // 1) pick up new or modified .cs files
            var files = Directory.GetFiles(_scriptsAbs, "*.cs", SearchOption.TopDirectoryOnly);
            foreach (var abs in files)
            {
                var rel = ToAssetRel(abs);
                var sha1 = SHA1Hex(File.ReadAllBytes(abs));
                var entry = _state.entries.FirstOrDefault(e => e.file == rel);

                if (entry == null)
                {
                    var cls = GuessClassName(File.ReadAllText(abs));
                    entry = new SeenEntry { file = rel, sha1 = sha1, className = cls, attached = false };
                    _state.entries.Add(entry);
                    L($"Detected new script: {rel}  class={cls}");
                    SaveJson(_stateAbs, _state);
                }
                else if (entry.sha1 != sha1)
                {
                    entry.sha1 = sha1;
                    entry.attached = false; // reattach on change
                    if (string.IsNullOrEmpty(entry.className))
                        entry.className = GuessClassName(File.ReadAllText(abs));
                    L($"Detected changed script: {rel}  class={entry.className}");
                    SaveJson(_stateAbs, _state);
                }
            }

            // 2) try attach not-yet-attached types
            foreach (var e in _state.entries.Where(x => !x.attached))
            {
                if (string.IsNullOrEmpty(e.className)) continue;
                var type = FindTypeByName(e.className);
                if (type == null)
                {
                    // Type not available yet (still compiling / domain just reloaded)
                    // Keep waiting silently; we scan again shortly.
                    continue;
                }

                var go = FindOrCreateTarget(e.className);
                if (go == null) { W($"No target for {e.className}"); continue; }

                if (go.GetComponent(type) == null)
                {
                    go.AddComponent(type);
                    L($"Attached {e.className} to '{go.name}' (Play).");

                    e.attached = true;
                    SaveJson(_stateAbs, _state);

                    if (_created.items.All(i => !(i.goName == go.name && i.className == e.className)))
                    {
                        _created.items.Add(new CreatedEntry { goName = go.name, className = e.className });
                        SaveJson(_createdAbs, _created);
                    }
                }
            }
        }

        // ---------------- helpers ----------------

        static string ToAbs(string assetPath)
        {
            if (string.IsNullOrEmpty(assetPath)) return Application.dataPath;
            assetPath = assetPath.Replace('\\', '/');
            if (!assetPath.StartsWith("Assets/") && assetPath != "Assets")
                return Path.GetFullPath(assetPath);
            return Path.Combine(Application.dataPath, assetPath.Substring("Assets/".Length));
        }

        static string ToAssetRel(string abs)
        {
            var dataRoot = Application.dataPath.Replace("\\", "/");
            var norm = abs.Replace("\\", "/");
            if (norm.StartsWith(dataRoot))
                return "Assets" + norm.Substring(dataRoot.Length);
            return abs.Replace("\\", "/");
        }

        static T LoadJson<T>(string abs) where T : class
        {
            try
            {
                if (!File.Exists(abs)) return null;
                var json = File.ReadAllText(abs, Encoding.UTF8);
                return JsonUtility.FromJson<T>(json);
            }
            catch { return null; }
        }

        static void SaveJson(string abs, object obj)
        {
            try
            {
                var dir = Path.GetDirectoryName(abs);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                var json = JsonUtility.ToJson(obj, true);
                File.WriteAllText(abs, json, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Debug.LogError($"[VoiceAttach] Failed writing '{abs}': {ex.Message}");
            }
        }

        static string SHA1Hex(byte[] data)
        {
            using var sha = SHA1.Create();
            var h = sha.ComputeHash(data);
            var sb = new StringBuilder(h.Length * 2);
            foreach (var b in h) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        static string GuessClassName(string source)
        {
            var m = Regex.Match(source ?? "", @"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)");
            return m.Success ? m.Groups[1].Value : "";
        }

        static Type FindTypeByName(string shortName)
        {
            var asms = AppDomain.CurrentDomain.GetAssemblies();
            foreach (var asm in asms.OrderBy(a => a.GetName().Name == "Assembly-CSharp" ? 0 : 1))
            {
                var t = asm.GetType(shortName, false, false);
                if (t != null) return t;
                var hit = asm.GetTypes().FirstOrDefault(x => x.Name == shortName);
                if (hit != null) return hit;
            }
            return null;
        }

        GameObject FindOrCreateTarget(string className)
        {
            // 1) existing object with same name
            var byName = GameObject.Find(className);
            if (byName != null) return byName;

            // 2) simple heuristics
            if (className.IndexOf("Player", StringComparison.OrdinalIgnoreCase) >= 0 ||
                className.IndexOf("Move", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                var tagged = SafeFindByTag("Player");
                if (tagged != null) return tagged;
                return new GameObject("Player");
            }

            if (className.IndexOf("Camera", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                if (Camera.main != null) return Camera.main.gameObject;
            }

            // 3) default: new object named after the class
            return new GameObject(className);
        }

        static GameObject SafeFindByTag(string tag)
        {
            try { return GameObject.FindGameObjectWithTag(tag); }
            catch { return null; }
        }

        // -------- Editor-only persistence hook (same file) --------
#if UNITY_EDITOR
        [UnityEditor.InitializeOnLoadMethod]
        static void HookEditorPersistence()
        {
            UnityEditor.EditorApplication.playModeStateChanged -= OnPlayModeStateChanged;
            UnityEditor.EditorApplication.playModeStateChanged += OnPlayModeStateChanged;
        }

        static void OnPlayModeStateChanged(UnityEditor.PlayModeStateChange change)
        {
            if (change == UnityEditor.PlayModeStateChange.EnteredEditMode)
            {
                try { PersistRuntimeCreations(); }
                catch (Exception ex) { Debug.LogError($"[VoiceAttach] Persist error: {ex.Message}"); }
            }
        }

        static void PersistRuntimeCreations()
        {
            var scriptsAbs = ToAbs("Assets/GeneratedScripts"); // default; will still work if you changed scriptsFolder at runtime
            var createdAbs = Path.Combine(scriptsAbs, CreatedFileName);
            if (!File.Exists(createdAbs)) return;

            var json = File.ReadAllText(createdAbs, Encoding.UTF8);
            var list = JsonUtility.FromJson<CreatedList>(json) ?? new CreatedList();
            if (list.items == null || list.items.Count == 0) return;

            int applied = 0;
            foreach (var item in list.items)
            {
                if (string.IsNullOrEmpty(item.className)) continue;
                var type = FindTypeByName(item.className);
                if (type == null)
                {
                    Debug.LogWarning($"[VoiceAttach] Persist skipped: type '{item.className}' not found.");
                    continue;
                }

                var go = GameObject.Find(item.goName);
                if (go == null) go = new GameObject(item.goName);

                if (go.GetComponent(type) == null)
                {
                    go.AddComponent(type);
                    applied++;
                    Debug.Log($"[VoiceAttach] Persisted {item.className} on '{go.name}' (Edit Mode).");
                }
            }

            if (applied > 0)
            {
                UnityEditor.SceneManagement.EditorSceneManager.MarkAllScenesDirty();
                UnityEditor.SceneManagement.EditorSceneManager.SaveOpenScenes();
                UnityEditor.AssetDatabase.SaveAssets();
            }

            // Clear so we don't re-apply next time
            File.WriteAllText(createdAbs, JsonUtility.ToJson(new CreatedList(), true), new UTF8Encoding(false));
        }
#endif
    }
}
