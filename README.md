# Flutter Client (iPhone)

A Flutter app that connects to the relay server, displays the live
Windows desktop stream, and turns touch gestures into mouse/keyboard
input. Styled with a dark, frosted "Liquid Glass" look.

## Requirements
- Flutter SDK: https://docs.flutter.dev/get-started/install
- Xcode (to run on iPhone or the iOS Simulator)
- An Apple Developer account is only needed to run on a *physical*
  iPhone (the Simulator works without one)

## Setup & Run

```bash
cd FlutterClient
flutter pub get

# List available devices/simulators:
flutter devices

# Run on a connected iPhone or the iOS simulator:
flutter run
```

On first launch, open the **settings** icon (bottom-right) and enter
your relay server's address, e.g. `ws://192.168.1.42:8080`, then tap
**Save**. The app will reconnect automatically using the new address.

## How to use it

| Gesture                    | Action                        |
|----------------------------|--------------------------------|
| Drag one finger             | Move the mouse (like a trackpad) |
| Tap once                    | Left click                     |
| Press and hold              | Right click                    |
| Drag two fingers up/down    | Scroll                         |
| Tap the keyboard icon       | Opens the on-screen keyboard for typing |

The bottom bar also has an audio mute/unmute toggle, a
connect/disconnect toggle, and a settings button.

## Audio playback
If the Windows host has "Stream system audio" enabled, you'll hear the
PC's system audio play through your phone automatically once connected
- no setup needed. Tap the speaker icon in the bottom bar to mute/unmute
it at any time (muting stops playback immediately but keeps receiving
data in the background, so unmuting is instant with no re-sync delay).

## Project structure

| File                                | Purpose                                                        |
|--------------------------------------|------------------------------------------------------------------|
| `lib/main.dart`                     | App entry point + dark theme setup.                             |
| `lib/screens/home_screen.dart`      | Main screen: desktop preview, touch input, controls.             |
| `lib/screens/settings_screen.dart`  | Relay server address input, persisted with `shared_preferences`. |
| `lib/services/remote_service.dart`  | Owns the WebSocket connection; splits incoming binary data into video frames vs. audio chunks and manages PCM playback. |
| `lib/widgets/touchpad_area.dart`    | Raw pointer-event handling for drag/tap/long-press/2-finger scroll, plus fading tap-ripple visual feedback. |
| `lib/widgets/glass_panel.dart`      | Reusable frosted-glass UI components with pulsing glow and press animations. |
| `lib/models/messages.dart`          | Builds the JSON messages sent to the relay/host.                 |

## Notes / known MVP limitations
- Mouse movement is *relative* (drag = move), not absolute-position
  tapping on the screen - this mirrors how a trackpad works and is far
  more usable on a small phone screen than 1:1 coordinate mapping.
- The on-screen keyboard uses a common "sentinel character" trick
  (see the comment in `home_screen.dart`) to detect both typed
  characters and backspace presses through Flutter's normal
  `TextField`, since the iOS software keyboard doesn't emit raw key
  events Flutter can listen to directly.
- No auto-reconnect/retry logic - use the connect/disconnect button in
  the bottom bar if the connection drops.
