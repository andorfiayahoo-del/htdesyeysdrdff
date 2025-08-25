#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.Compilation;
using UnityEngine;
using System;
using System.IO;

namespace Ops {
    [Serializable]
    public class CompileStatus {
        public string state;
        public string utc;
        public bool isCompiling;
        public bool isUpdating;
        public string[] assemblies;
    }

    [InitializeOnLoad]
    public static class CompileSentinel {
        static readonly string Root = Path.GetDirectoryName(Application.dataPath);
        static readonly string LiveDir = Path.Combine(Root, "ops", "live");
        static readonly string Sentinel = Path.Combine(LiveDir, "unity-compile.json");

        static CompileSentinel() {
            Directory.CreateDirectory(LiveDir);
            Write("Initialized");
            CompilationPipeline.compilationStarted  += _ => Write("Compiling");
            CompilationPipeline.compilationFinished += _ => Write("Compiled");
        }

        static void Write(string state) {
            try {
                var st = new CompileStatus {
                    state = state,
                    utc = DateTime.UtcNow.ToString("o"),
                    isCompiling = EditorApplication.isCompiling || CompilationPipeline.isCompiling,
                    isUpdating  = EditorApplication.isUpdating,
                    assemblies  = new string[0]
                };
                File.WriteAllText(Sentinel, JsonUtility.ToJson(st, true));
                Debug.Log("[Ops] CompileSentinel wrote " + state + " -> " + Sentinel);
            } catch (Exception e) {
                Debug.LogWarning("[Ops] CompileSentinel write failed: " + e.Message);
            }
        }

        // CLI helpers
        public static void EmitStatusCLI() { Write("Ping"); }
        public static void WaitForCompileCLI() {
            while (EditorApplication.isCompiling || CompilationPipeline.isCompiling || EditorApplication.isUpdating)
                System.Threading.Thread.Sleep(200);
            AssetDatabase.Refresh();
            while (EditorApplication.isCompiling || CompilationPipeline.isCompiling || EditorApplication.isUpdating)
                System.Threading.Thread.Sleep(200);
            Write("Compiled");
            Debug.Log("[Ops] WaitForCompileCLI done.");
        }
    }
}
#endif