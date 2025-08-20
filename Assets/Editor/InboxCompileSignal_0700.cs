#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

[InitializeOnLoad]
public static class InboxCompileSignal_0700
{
    static InboxCompileSignal_0700()
    {
        try
        {
            var stamp = System.IO.Path.Combine(Application.dataPath, "InboxPatches", "CompileDone.stamp");
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(stamp));
            System.IO.File.WriteAllText(stamp, System.DateTime.UtcNow.ToString("o"));
            Debug.Log("[Inbox] Wrote CompileDone.stamp");
        }
        catch (System.Exception ex)
        {
            Debug.LogWarning("[Inbox] Failed to write CompileDone.stamp: " + ex.Message);
        }
    }
}
#endif
