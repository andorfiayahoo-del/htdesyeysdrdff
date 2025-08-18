#if UNITY_EDITOR
using System;
using UnityEditor;
using UnityEngine;

[InitializeOnLoad]
public static class ReceiverLogFilter
{
    private sealed class FilteringLogHandler : ILogHandler
    {
        private readonly ILogHandler _inner;

        public FilteringLogHandler(ILogHandler inner) => _inner = inner;

        public void LogException(Exception exception, UnityEngine.Object context)
        {
            // Pass through exceptions normally
            _inner.LogException(exception, context);
        }

        public void LogFormat(LogType logType, UnityEngine.Object context, string format, params object[] args)
        {
            try
            {
                string msg = string.Format(format, args);

                // Quiet the expected socket churn during editor domain reloads / imports.
                if (logType == LogType.Error &&
                    (msg.Contains("WSACancelBlockingCall") ||
                     msg.Contains("failed to respond") ||
                     msg.Contains("connection was aborted by the software in your host machine")))
                {
                    Debug.unityLogger.logHandler = _inner; // avoid recursion
                    Debug.Log("[Receiver] Listener cancelled during reload (expected).");
                    Debug.unityLogger.logHandler = this;
                    return;
                }

                _inner.LogFormat(logType, context, format, args);
            }
            catch
            {
                // If anything goes wrong, fall back to inner to avoid swallowing logs
                _inner.LogFormat(logType, context, format, args);
            }
        }
    }

    static ReceiverLogFilter()
    {
        // Wrap the global logger only in the editor.
        var original = Debug.unityLogger.logHandler;
        if (original is FilteringLogHandler) return; // already wrapped
        Debug.unityLogger.logHandler = new FilteringLogHandler(original);
        Debug.Log("[ReceiverLogFilter] Active");
    }
}
#endif
