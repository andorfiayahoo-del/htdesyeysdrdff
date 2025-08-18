// Assets/Editor/CleanupMissingScripts.cs
// Removes missing MonoBehaviour components from scenes & prefabs, using modern Unity APIs (no obsolete FindObjectsOfType).
// Menu: Tools/Cleanup/...

using System.Collections.Generic;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

public static class CleanupMissingScripts
{
    [MenuItem("Tools/Cleanup/Remove Missing Scripts In Open Scenes")]
    public static void RemoveInOpenScenes()
    {
        int totalRemoved = 0;

        for (int i = 0; i < EditorSceneManager.sceneCount; i++)
        {
            var scene = EditorSceneManager.GetSceneAt(i);
            if (!scene.isLoaded) continue;

            foreach (var root in scene.GetRootGameObjects())
            {
                totalRemoved += RemoveFromHierarchy(root);
            }

            if (totalRemoved > 0)
            {
                EditorSceneManager.MarkSceneDirty(scene);
            }
        }

        Debug.Log($"[Cleanup] Removed {totalRemoved} missing script component(s) from open scenes.");
    }

    [MenuItem("Tools/Cleanup/Remove Missing Scripts In Entire Project")]
    public static void RemoveEverywhere()
    {
        int totalRemoved = 0;

        // 1) Scenes in the project
        var sceneGuids = AssetDatabase.FindAssets("t:Scene");
        for (int i = 0; i < sceneGuids.Length; i++)
        {
            var path = AssetDatabase.GUIDToAssetPath(sceneGuids[i]);
            var scene = EditorSceneManager.OpenScene(path, OpenSceneMode.Additive);
            int removedInScene = 0;

            foreach (var root in scene.GetRootGameObjects())
            {
                removedInScene += RemoveFromHierarchy(root);
            }

            if (removedInScene > 0)
            {
                EditorSceneManager.MarkSceneDirty(scene);
                EditorSceneManager.SaveScene(scene);
            }

            totalRemoved += removedInScene;
            EditorSceneManager.CloseScene(scene, true);
        }

        // 2) Prefabs in the project
        var prefabGuids = AssetDatabase.FindAssets("t:Prefab");
        for (int i = 0; i < prefabGuids.Length; i++)
        {
            var path = AssetDatabase.GUIDToAssetPath(prefabGuids[i]);
            var prefabRoot = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (!prefabRoot) continue;

            // Edit prefab contents safely
            var stageRoot = PrefabUtility.LoadPrefabContents(path);
            int removedInPrefab = RemoveFromHierarchy(stageRoot);
            if (removedInPrefab > 0)
            {
                PrefabUtility.SaveAsPrefabAsset(stageRoot, path);
            }
            PrefabUtility.UnloadPrefabContents(stageRoot);

            totalRemoved += removedInPrefab;
        }

        Debug.Log($"[Cleanup] Removed {totalRemoved} missing script component(s) from all scenes & prefabs.");
    }

    private static int RemoveFromHierarchy(GameObject root)
    {
        int removed = 0;
        // Remove on this object
        removed += GameObjectUtility.RemoveMonoBehavioursWithMissingScript(root);

        // Recurse children (no obsolete API here)
        var stack = new Stack<Transform>();
        stack.Push(root.transform);

        while (stack.Count > 0)
        {
            var t = stack.Pop();
            foreach (Transform child in t)
            {
                removed += GameObjectUtility.RemoveMonoBehavioursWithMissingScript(child.gameObject);
                stack.Push(child);
            }
        }

        return removed;
    }
}
