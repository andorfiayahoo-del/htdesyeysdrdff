using UnityEngine;

public class VoiceCommandListener : MonoBehaviour
{
    [Header("Movement Settings")]
    public float moveSpeed = 5f;

    private bool shouldMove = false;

    void Start()
    {
        Debug.Log("VoiceCommandListener is active.");
    }

    void Update()
    {
        // Simulated voice input using spacebar for now
        if (Input.GetKeyDown(KeyCode.Space))
        {
            shouldMove = !shouldMove;
            Debug.Log("Simulated Voice Command: " + (shouldMove ? "Move ON" : "Move OFF"));
        }

        if (shouldMove)
        {
            transform.Translate(Vector3.forward * moveSpeed * Time.deltaTime);
        }
    }

    // Placeholder for future voice commands
    public void HandleVoiceCommand(string command)
    {
        switch (command.ToLower())
        {
            case "move":
                shouldMove = true;
                break;
            case "stop":
                shouldMove = false;
                break;
            default:
                Debug.LogWarning("Unknown voice command: " + command);
                break;
        }
    }
}
