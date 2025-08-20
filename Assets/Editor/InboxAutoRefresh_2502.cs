#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
[InitializeOnLoad]
public static class InboxAutoRefresh_2502
{
    static InboxAutoRefresh_2502()
    {
        EditorApplication.update += DoOnce;
    }
    private static void DoOnce()
    {
        EditorApplication.update -= DoOnce;
        AssetDatabase.Refresh(ImportAssetOptions.Default);
        Debug.Log("[Inbox] Auto-refresh 2502 complete.");
    }
}
#endif

