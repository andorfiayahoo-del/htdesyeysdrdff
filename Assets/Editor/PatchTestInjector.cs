#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using UnityEditor.SceneManagement;

public static class PatchTestInjector
{
    [MenuItem("Tools/Patch Test/Create Red Cube")]
    public static void CreateCube()
    {
        var go = GameObject.Find("PATCH_TEST_CUBE");
        if (go == null)
        {
            go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "PATCH_TEST_CUBE";
            go.transform.position = new Vector3(0f, 1f, 0f);

            var r = go.GetComponent<Renderer>();
            if (r != null)
            {
                var shader = Shader.Find("Universal Render Pipeline/Lit");
                if (shader == null) shader = Shader.Find("Standard");
                if (shader != null)
                {
                    var mat = new Material(shader);
                    if (shader.name.Contains("Universal"))
                        mat.SetColor("_BaseColor", new Color(1f, 0.25f, 0.25f, 1f));
                    else
                        mat.color = new Color(1f, 0.25f, 0.25f, 1f);
                    r.sharedMaterial = mat;
                }
            }
        }

        Selection.activeObject = go;
        EditorSceneManager.MarkSceneDirty(EditorSceneManager.GetActiveScene());
        Debug.Log("[PatchTest] Create Red Cube (menu)");
    }
}
#endif
