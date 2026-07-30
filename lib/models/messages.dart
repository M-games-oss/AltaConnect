import 'dart:convert';

/// This file defines the JSON message "shapes" used to talk to the
/// relay server / Windows host. It mirrors the protocol documented in
/// `RelayServer/server.js` and `WindowsHost/Messages.cs`.
///
/// Everything here is a simple function that returns a JSON string,
/// ready to hand straight to a WebSocketChannel.sink.add(...) call.
class RemoteMessages {
  RemoteMessages._();

  /// Sent once, immediately after connecting, so the relay knows this
  /// socket is the phone (as opposed to the Windows host).
  static String registerAsPhone() => jsonEncode({
        'type': 'register',
        'role': 'phone',
      });

  /// Relative mouse movement, like a laptop touchpad. dx/dy are in
  /// logical pixels of on-screen finger movement (scaled by a
  /// sensitivity factor before sending - see TouchpadArea).
  static String mouseMove(double dx, double dy) => jsonEncode({
        'type': 'mousemove',
        'dx': dx,
        'dy': dy,
      });

  /// A full click (press + release) of a mouse button.
  static String click(String button) => jsonEncode({
        'type': 'click',
        'button': button, // "left" or "right"
      });

  /// Mouse wheel scroll. Positive = scroll up, negative = scroll down.
  static String scroll(double delta) => jsonEncode({
        'type': 'scroll',
        'delta': delta,
      });

  /// Typed text characters from the on-screen keyboard.
  static String text(String value) => jsonEncode({
        'type': 'text',
        'text': value,
      });

  /// A special key press, e.g. "backspace", "enter", "space", "tab".
  static String key(String keyName) => jsonEncode({
        'type': 'key',
        'key': keyName,
      });
}
