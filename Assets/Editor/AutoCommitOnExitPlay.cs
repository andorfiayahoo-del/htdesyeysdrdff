#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using System;
using System.IO;
using System.Diagnostics;

[InitializeOnLoad]
public static class AutoCommitOnExitPlay
{
    static bool wasPlaying = false;

    static AutoCommitOnExitPlay()
    {
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
    }

    static void OnPlayModeChanged(PlayModeStateChange state)
    {
        if (state == PlayModeStateChange.EnteredPlayMode)
        {
            wasPlaying = true;
        }
        else if (state == PlayModeStateChange.EnteredEditMode && wasPlaying)
        {
            wasPlaying = false;
            TryCommitWithLogs();
        }
    }

    static void TryCommitWithLogs()
    {
        try
        {
            // Save scenes to make sure changes are captured
            EditorSceneManager.SaveOpenScenes();

            // Ensure Logs folder exists in project
            var logsDir = Path.Combine(Application.dataPath, "Logs");
            if (!Directory.Exists(logsDir)) Directory.CreateDirectory(logsDir);

            // Timestamp for filenames
            var ts = DateTime.Now.ToString("yyyyMMdd-HHmmss");

            // 1) Copy Unity Editor log → Assets/Logs/Editor-*.log
            // Windows Editor.log path:
            string editorLog = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Unity", "Editor", "Editor.log"
            );
            if (File.Exists(editorLog))
            {
                File.Copy(editorLog, Path.Combine(logsDir, $"Editor-{ts}.log"), true);
            }

            // 2) Copy your scheduled-task log → Assets/Logs/AutoPull-*.log (if present)
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string autoPullLog = Path.Combine(userProfile, "unity-autopull.log");
            if (File.Exists(autoPullLog))
            {
                File.Copy(autoPullLog, Path.Combine(logsDir, $"AutoPull-{ts}.log"), true);
            }

            // 3) Kick your quick-push script
            string gp = Path.Combine(userProfile, "gp.ps1");
            if (File.Exists(gp))
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{gp}\"",
                    WorkingDirectory = Directory.GetCurrentDirectory(),
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };
                using (var p = Process.Start(psi))
                {
                    // Optional: wait briefly so it finishes before you immediately hit Play again
                    p.WaitForExit(20000);
                }
                UnityEngine.Debug.Log("[AutoCommit] Logs copied and gp.ps1 pushed to GitHub.");
            }
            else
            {
                UnityEngine.Debug.LogWarning("[AutoCommit] gp.ps1 not found in user profile—skipping push.");
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogError("[AutoCommit] Failed: " + ex.Message);
        }
    }
}
#endif
