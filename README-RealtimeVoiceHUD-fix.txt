# RealtimeVoiceHUD fix

This replaces `Assets/Scripts/Realtime/RealtimeVoiceHUD.cs` and removes hard
dependencies on specific properties (e.g., `IsConnected`, `IsSpeaking`,
`MicDeviceInUse`, `LastDb`, and `BufferFill01`).

The new HUD queries those values **via reflection** so it stays compatible
with your current `RealtimeVoiceClient` and `StreamingAudioPlayer` implementations,
whatever their exact field/property names are.

## Install
1. Unzip at your project root so the path becomes:
   `Assets/Scripts/Realtime/RealtimeVoiceHUD.cs`
2. Let Unity recompile.

You're good to go.
