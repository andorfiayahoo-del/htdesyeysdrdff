using UnityEngine;

public class MicrophoneAccessTest : MonoBehaviour
{
    void Start()
    {
        if (Microphone.devices.Length > 0)
        {
            Debug.Log("Microphone detected: " + Microphone.devices[0]);
            AudioClip testClip = Microphone.Start(null, false, 1, 44100);
        }
        else
        {
            Debug.LogWarning("No microphone detected.");
        }
    }
}
