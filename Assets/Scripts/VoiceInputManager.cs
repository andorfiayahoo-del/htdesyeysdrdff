using UnityEngine;
using System.Speech.Recognition;
using System.Globalization;

public class VoiceInputManager : MonoBehaviour
{
    private SpeechRecognitionEngine recognizer;
    public VoiceCommandListener target;

    void Start()
    {
        if (target == null)
        {
            Debug.LogError("VoiceInputManager: No target set!");
            return;
        }

        try
        {
            // Attempt to create the recognizer directly
            recognizer = new SpeechRecognitionEngine(new CultureInfo("en-US"));

            // Create grammar
            Choices commands = new Choices(new string[] { "move", "stop" });
            GrammarBuilder gb = new GrammarBuilder(commands);
            Grammar grammar = new Grammar(gb);

            recognizer.LoadGrammar(grammar);
            recognizer.SetInputToDefaultAudioDevice();

            recognizer.SpeechRecognized += (s, e) =>
            {
                Debug.Log("Recognized: " + e.Result.Text);
                target.HandleVoiceCommand(e.Result.Text);
            };

            recognizer.RecognizeAsync(RecognizeMode.Multiple);

            Debug.Log("Voice recognition initialized successfully.");
        }
        catch (System.Exception ex)
        {
            Debug.LogError("Voice recognition failed to start: " + ex.Message);
        }
    }

    void OnApplicationQuit()
    {
        if (recognizer != null)
        {
            recognizer.RecognizeAsyncStop();
            recognizer.Dispose();
        }
    }
}
