using UnityEditor;
using UnityEditor.Callbacks;
using UnityEngine;
using System.IO;
using System;

public static class OpsCompileSignal
{
    [DidReloadScripts]
    private static void OnReloaded()
    {
        try
        {
            var projectRoot = Directory.GetParent(Application.dataPath).FullName;
            var liveDir = Path.Combine(projectRoot, "ops", "live");
            var trigger = Path.Combine(liveDir, "compile-trigger.txt");
            if (!File.Exists(trigger)) return;

            var token = File.ReadAllText(trigger).Trim();
            if (string.IsNullOrEmpty(token)) return;

            var ack = Path.Combine(liveDir, "compile-ack_" + token + ".txt");
            File.WriteAllText(ack, DateTime.UtcNow.ToString("o"));
            Debug.Log("[OpsCompileSignal] ack " + token);
        }
        catch (Exception ex)
        {
            Debug.LogWarning("[OpsCompileSignal] exception: " + ex.Message);
        }
    }
}