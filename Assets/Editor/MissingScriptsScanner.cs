#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using UnityEngine.SceneManagement;

public static class MissingScriptsScanner
{
    [MenuItem("Tools/VoiceBridge/Report Missing Scripts in Open Scenes")]
    public static void ReportMissingInOpenScenes()
    {
        int totalGO = 0, totalMissing = 0;
        for (int si = 0; si < SceneManager.sceneCount; si++)
        {
            var scene = SceneManager.GetSceneAt(si);
            if (!scene.isLoaded) continue;
            foreach (var root in scene.GetRootGameObjects())
            {
                ScanGO(root, ref totalGO, ref totalMissing);
            }
        }
        Debug.Log($"[MissingScriptsScanner] Scanned {totalGO} GameObjects, missing components: {totalMissing}");
    }

    static void ScanGO(GameObject go, ref int totalGO, ref int totalMissing)
    {
        totalGO++;
        var comps = go.GetComponents<Component>();
        for (int i = 0; i < comps.Length; i++)
        {
            if (comps[i] == null)
            {
                string path = GetPath(go);
                Debug.LogWarning($"[MissingScriptsScanner] Missing script on '{path}' (component index {i})", go);
                totalMissing++;
            }
        }
        foreach (Transform child in go.transform)
            ScanGO(child.gameObject, ref totalGO, ref totalMissing);
    }

    static string GetPath(GameObject go)
    {
        string path = go.name;
        var t = go.transform;
        while (t.parent != null)
        {
            t = t.parent;
            path = t.name + "/" + path;
        }
        return path;
    }
}
#endif
//