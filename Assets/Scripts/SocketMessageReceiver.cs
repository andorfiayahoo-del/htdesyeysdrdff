using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Collections.Concurrent;
using UnityEngine;

public class SocketMessageReceiver : MonoBehaviour
{
    private TcpListener listener;
    private Thread listenerThread;
    private ConcurrentQueue<string> receivedMessages = new ConcurrentQueue<string>();
    private bool isRunning = false;

    void Start()
    {
        listenerThread = new Thread(ListenForMessages);
        listenerThread.IsBackground = true;
        listenerThread.Start();
    }

    void Update()
    {
        while (receivedMessages.TryDequeue(out string message))
        {
            Debug.Log("Received from client: " + message);
        }
    }

    void ListenForMessages()
    {
        try
        {
            listener = new TcpListener(IPAddress.Loopback, 65432);
            listener.Start();
            isRunning = true;
            Debug.Log("Server listening on port 65432");

            while (isRunning)
            {
                TcpClient client = listener.AcceptTcpClient();
                NetworkStream stream = client.GetStream();
                byte[] buffer = new byte[1024];

                while (isRunning && client.Connected)
                {
                    int bytesRead = stream.Read(buffer, 0, buffer.Length);
                    if (bytesRead <= 0) break;

                    string message = Encoding.UTF8.GetString(buffer, 0, bytesRead);
                    receivedMessages.Enqueue(message);
                }

                client.Close();
            }
        }
        catch (SocketException e)
        {
            Debug.LogError("Socket error: " + e.Message);
        }
        catch (Exception e)
        {
            Debug.LogError("Unexpected error: " + e.Message);
        }
        finally
        {
            listener?.Stop();
        }
    }

    void OnApplicationQuit()
    {
        isRunning = false;
        listener?.Stop();
        listenerThread?.Abort();
    }
}
