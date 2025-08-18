#if UNITY_EDITOR
using System;
using System.Collections.Concurrent;
using System.Threading;
using UnityEditor;
using UnityEngine;

[InitializeOnLoad]
public static class EditorMainThread
{
    static readonly ConcurrentQueue<Action> _queue = new ConcurrentQueue<Action>();
    static readonly int _mainThreadId;
    const int MaxActionsPerUpdate = 128; // keep the editor snappy

    static EditorMainThread()
    {
        _mainThreadId = Thread.CurrentThread.ManagedThreadId;
        EditorApplication.update += Drain;

        // Optional: clear any stale actions right before domain reload
        AssemblyReloadEvents.beforeAssemblyReload += () =>
        {
            while (_queue.TryDequeue(out _)) { }
        };
    }

    /// <summary>Always safe to call from worker threads.</summary>
    public static void Enqueue(Action action)
    {
        if (action == null) return;
        _queue.Enqueue(action);
    }

    /// <summary>If called on the main thread, run immediately; else enqueue.</summary>
    public static void EnqueueOrRun(Action action)
    {
        if (action == null) return;
        if (Thread.CurrentThread.ManagedThreadId == _mainThreadId)
        {
            try { action(); }
            catch (Exception ex) { Debug.LogError($"[EditorMainThread] {ex}"); }
        }
        else
        {
            _queue.Enqueue(action);
        }
    }

    static void Drain()
    {
        int processed = 0;
        while (processed < MaxActionsPerUpdate && _queue.TryDequeue(out var a))
        {
            try { a(); }
            catch (Exception ex) { Debug.LogError($"[EditorMainThread] {ex}"); }
            processed++;
        }
    }

    /// <summary>Debug hint only; not exact.</summary>
    public static int ApproxQueueLength => _queue.Count;
}
#endif
