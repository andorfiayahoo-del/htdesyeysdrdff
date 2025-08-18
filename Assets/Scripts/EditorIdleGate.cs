// Assets/Editor/EditorIdleGate.cs
#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
using System.Threading;

[InitializeOnLoad]
public static class EditorIdleGate
{
    // Tracks whether we're busy with an import/compile/reload cycle
    private static volatile int _pendingScripts;   // count of scripts we expect to import
    private static volatile bool _importing;       // we triggered an import
    private static volatile bool _reloading;       // domain reload in progress

    static string T => System.DateTime.Now.ToString("HH:mm:ss.fff");
    static void L(string msg)  => Debug.Log($"[{T}] [EditorIdleGate] {msg}");

    static EditorIdleGate()
    {
        // Domain reload markers
        AssemblyReloadEvents.beforeAssemblyReload += () =>
        {
            _reloading = true;
            L("Domain reload starting…");
        };
        AssemblyReloadEvents.afterAssemblyReload += () =>
        {
            _reloading = false;
            L("Domain reload finished.");
        };

        // Lightweight heartbeat (reserved for future heuristics)
        EditorApplication.update += () => { };

        L("Ready");
    }

    /// <summary>
    /// True when it's safe to reconnect to Python and accept the next script.
    /// </summary>
    public static bool IsEditorIdle =>
        !EditorApplication.isCompiling &&
        !EditorApplication.isUpdating &&
        !_reloading &&
        !_importing &&
        _pendingScripts == 0;

    /// <summary>
    /// Call when a script is about to arrive (before writing the file).
    /// </summary>
    public static void AnnounceIncomingScript()
    {
        Interlocked.Increment(ref _pendingScripts);
        L("Incoming script announced.");
    }

    /// <summary>
    /// Call on the main thread right before ImportAsset.
    /// </summary>
    public static void NotifyImportRequested()
    {
        _importing = true;
        L("Import requested.");
    }

    /// <summary>
    /// Call on the main thread after ImportAsset/SaveAssets returns.
    /// This also balances the pending counter.
    /// </summary>
    public static void NotifyImportFinished()
    {
        _importing = false;
        if (_pendingScripts > 0) Interlocked.Decrement(ref _pendingScripts);
        L("Import finished.");
    }
}
#endif
