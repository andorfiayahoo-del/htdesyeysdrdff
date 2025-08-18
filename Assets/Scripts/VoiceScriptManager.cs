using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using UnityEngine;

public class VoiceScriptManager : MonoBehaviour
{
    private TcpClient client;
    private NetworkStream stream;
    private byte[] buffer = new byte[8192];
    private string receivedData = "";

    [Tooltip("Folder path relative to Assets where scripts will be saved.")]
    public string scriptSaveFolder = "Scripts/Generated";

    void Start()
    {
        try
        {
            client = new TcpClient("127.0.0.1", 65433); // New port for script gen
            stream = client.GetStream();
            Debug.Log("🧠 VoiceScriptManager is ready to receive script code.");
        }
        catch (Exception e)
        {
            Debug.LogError($"Script socket connection error: {e.Message}");
        }
    }

    void Update()
    {
        if (stream != null && stream.DataAvailable)
        {
            int bytesRead = stream.Read(buffer, 0, buffer.Length);
            receivedData += Encoding.UTF8.GetString(buffer, 0, bytesRead);

            int delimiterIndex;
            while ((delimiterIndex = receivedData.IndexOf("<ENDSCRIPT>")) != -1)
            {
                string fullScript = receivedData.Substring(0, delimiterIndex).Trim();
                receivedData = receivedData.Substring(delimiterIndex + "<ENDSCRIPT>".Length);
                SaveScript(fullScript);
            }
        }
    }

    void SaveScript(string scriptContent)
    {
        string scriptName = "GeneratedScript_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".cs";
        string savePath = Path.Combine(Application.dataPath, scriptSaveFolder);

        if (!Directory.Exists(savePath))
            Directory.CreateDirectory(savePath);

        string fullPath = Path.Combine(savePath, scriptName);
        File.WriteAllText(fullPath, scriptContent);

        Debug.Log($"✅ Script saved: {fullPath}");
#if UNITY_EDITOR
        UnityEditor.AssetDatabase.Refresh();
#endif
    }

    void OnApplicationQuit()
    {
        stream?.Close();
        client?.Close();
    }
}
