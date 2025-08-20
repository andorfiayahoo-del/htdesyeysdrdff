#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

[InitializeOnLoad]
public static class InboxAutoRefresh_0403
{
    static InboxAutoRefresh_0403()
    {
        EditorApplication.update += DoOnce;
    }

    private static void DoOnce()
    {
        EditorApplication.update -= DoOnce;
        AssetDatabase.Refresh(ImportAssetOptions.Default);
        Debug.Log("[Inbox] Auto-refresh 0403 complete.");
    }
}
#endif
