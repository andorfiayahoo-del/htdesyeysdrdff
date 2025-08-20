#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
[InitializeOnLoad]
public static class InboxCompileSignal_2501
{
    static InboxCompileSignal_2501()
    {
        try
        {
            var stamp = System.IO.Path.Combine(Application.dataPath, "InboxPatches", "CompileDone.stamp");
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(stamp));
            System.IO.File.WriteAllText(stamp, System.DateTime.UtcNow.ToString("o"));
            Debug.Log("[Inbox] 2501 wrote CompileDone.stamp");
        }
        catch (System.Exception ex)
        {
            Debug.LogWarning("[Inbox] 2501 failed to write CompileDone.stamp: " + ex.Message);
        }
    }
}
#endif

