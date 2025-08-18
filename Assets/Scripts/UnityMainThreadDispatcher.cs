using System;
using System.Collections.Generic;
using UnityEngine;

public class UnityMainThreadDispatcher : MonoBehaviour
{
    private static readonly Queue<Action> executionQueue = new Queue<Action>();

    public static void Enqueue(Action action)
    {
        lock (executionQueue)
        {
            executionQueue.Enqueue(action);
        }
    }

    void Update()
    {
        while (executionQueue.Count > 0)
        {
            Action action;
            lock (executionQueue)
            {
                action = executionQueue.Dequeue();
            }
            action?.Invoke();
        }
    }
}
