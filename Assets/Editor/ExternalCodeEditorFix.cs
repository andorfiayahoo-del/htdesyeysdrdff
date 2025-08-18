#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

public static class ExternalCodeEditorFix
{
    [MenuItem("Tools/External Editor/Set Editor Path…")]
    public static void SetExternalEditorPath()
    {
        var path = EditorUtility.OpenFilePanel("Select external code editor executable", "", "");
        if (!string.IsNullOrEmpty(path))
        {
            // This key is what Unity uses for the external editor path across versions.
            EditorPrefs.SetString("kScriptsDefaultApp", path);
            Debug.Log($"[ExternalEditor] Set to: {path}");
            SettingsService.OpenUserPreferences("Preferences/External Tools");
        }
    }

    [MenuItem("Tools/External Editor/Open Preferences")]
    public static void OpenPreferences()
    {
        SettingsService.OpenUserPreferences("Preferences/External Tools");
    }
}
#endif
