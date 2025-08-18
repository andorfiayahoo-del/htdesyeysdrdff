#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using UnityEditor.SceneManagement;

[InitializeOnLoad]
public static class PatchTestInjector
{
    static PatchTestInjector()
    {
        // After scripts reload, run once
        EditorApplication.delayCall += () => CreateCube(false);
    }

    [MenuItem("Tools/Patch Test/Create Red Cube (force)")]
    public static void CreateCubeMenu()
    {
        CreateCube(true);
    }

    private static void CreateCube(bool force)
    {
        const string Flag = "PatchTestInjected_v1";
        if (!force && SessionState.GetBool(Flag, false)) return;

        var existing = GameObject.Find("PATCH_TEST_CUBE");
        if (existing == null)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "PATCH_TEST_CUBE";
            go.transform.position = new Vector3(0f, 1f, 0f);

            var renderer = go.GetComponent<Renderer>();
            if (renderer != null)
            {
                // Try URP Lit first, then Standard
                var shader = Shader.Find("Universal Render Pipeline/Lit");
                if (shader == null) shader = Shader.Find("Standard");
                if (shader != null)
                {
                    var mat = new Material(shader);
                    // URP Lit uses _BaseColor, Standard uses .color
                    if (shader.name.Contains("Universal"))
                        mat.SetColor("_BaseColor", new Color(1f, 0.25f, 0.25f, 1f));
                    else
                        mat.color = new Color(1f, 0.25f, 0.25f, 1f);
                    renderer.sharedMaterial = mat;
                }
            }

            EditorGUIUtility.PingObject(go);
            EditorSceneManager.MarkSceneDirty(EditorSceneManager.GetActiveScene());
            Debug.Log("[PatchTest] Spawned PATCH_TEST_CUBE at (0,1,0).");
        }
        SessionState.SetBool(Flag, true);
    }
}
#endif
