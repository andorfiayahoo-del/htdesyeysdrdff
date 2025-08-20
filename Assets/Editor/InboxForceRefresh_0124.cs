#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

[InitializeOnLoad]
public static class InboxForceRefresh_0124
{
    static InboxForceRefresh_0124()
    {
        // Run once on editor load to ensure assets are refreshed after patch application
        EditorApplication.update += DoOnce;
    }

    private static void DoOnce()
    {
        EditorApplication.update -= DoOnce;
        AssetDatabase.Refresh(ImportAssetOptions.Default);
        Debug.Log("[Inbox] Forced refresh after patch 0124.");
    }
}
