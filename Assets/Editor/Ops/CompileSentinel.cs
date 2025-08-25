using UnityEditor;
using UnityEngine;
using System;
using System.IO;
using System.Text;

namespace Ops {
  [InitializeOnLoad]
  public static class CompileSentinel {
    static readonly string ProjectRoot;
    static readonly string SentinelPath;
    static bool lastC, lastU;
    static DateTime lastWriteUtc;

    static CompileSentinel() {
      try {
        var assets = Application.dataPath;
        ProjectRoot = Directory.GetParent(assets).FullName;
        SentinelPath = Path.Combine(ProjectRoot, "ops", "live", "unity-compile.json");
        EditorApplication.update += OnUpdate;
        WriteStatus(true);
      } catch { /* swallow */ }
    }

    [MenuItem("Ops/Emit Compile Sentinel Once")]
    public static void EmitOnce() { WriteStatus(true); }

    static void OnUpdate() {
      try {
        bool c = EditorApplication.isCompiling;
        bool u = EditorApplication.isUpdating;
        if (c != lastC || u != lastU) { WriteStatus(true); return; }
        if (c || u) {
          if ((DateTime.UtcNow - lastWriteUtc).TotalSeconds > 2)
            WriteStatus(false);
        }
      } catch { /* swallow */ }
    }

    static void WriteStatus(bool force) {
      try {
        bool c = EditorApplication.isCompiling;
        bool u = EditorApplication.isUpdating;
        var dir = Path.GetDirectoryName(SentinelPath);
        Directory.CreateDirectory(dir);
        var json = "{\"isCompiling\":" + (c ? "true" : "false") + "," +
                   "\"isUpdating\":" + (u ? "true" : "false") + "," +
                   "\"timestamp\":\"" + DateTime.UtcNow.ToString("o") + "\"}";
        File.WriteAllText(SentinelPath, json, new UTF8Encoding(false));
        lastC = c; lastU = u; lastWriteUtc = DateTime.UtcNow;
      } catch { /* swallow */ }
    }
  }
}
