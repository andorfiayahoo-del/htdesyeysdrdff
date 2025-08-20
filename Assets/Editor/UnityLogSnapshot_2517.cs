#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using System.IO;
[InitializeOnLoad]
public static class UnityLogSnapshot_2517
{
    static UnityLogSnapshot_2517()
    {
        try
        {
            // Compute Editor.log path on Windows (fallback to LocalAppData)
            var local = System.Environment.GetFolderPath(System.Environment.SpecialFolder.LocalApplicationData);
            var editorLog = Path.Combine(local, "Unity", "Editor", "Editor.log");
            var projLogsDir = Path.Combine(Application.dataPath, "InboxPatches", "Logs", "Unity");
            Directory.CreateDirectory(projLogsDir);
            var dest = Path.Combine(projLogsDir, "EditorLog_snapshot.txt");
            if (File.Exists(editorLog))
            {
                // Copy last ~2000 lines to keep size modest
                var all = File.ReadAllLines(editorLog);
                int take = Mathf.Min(2000, all.Length);
                File.WriteAllLines(dest, new System.ArraySegment<string>(all, all.Length - take, take));
            }
            else
            {
                File.WriteAllText(dest, "Editor.log not found at " + editorLog);
            }

            // Stamp compile-done (kept for router handshake)
            var stamp = Path.Combine(Application.dataPath, "InboxPatches", "CompileDone.stamp");
            Directory.CreateDirectory(Path.GetDirectoryName(stamp));
            File.WriteAllText(stamp, System.DateTime.UtcNow.ToString("o"));
            Debug.Log("[Inbox] UnityLogSnapshot_2517 wrote CompileDone.stamp and snapshot.");
        }
        catch (System.Exception ex)
        {
            Debug.LogWarning("[Inbox] UnityLogSnapshot_2517 failed: " + ex.Message);
        }
    }
}
#endif

