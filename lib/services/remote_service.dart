import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/messages.dart';

/// The three states the connection to the relay server can be in.
enum ConnectionStatus { disconnected, connecting, connected, error }

/// Tag bytes prepended to every binary message coming from the Windows
/// host (via the relay), so we know whether it's a video frame or an
/// audio chunk. Must match WindowsHost/RelayClient.cs.
const int _tagVideoFrame = 0x01;
const int _tagAudioChunk = 0x02;

// Audio format sent by the host - see WindowsHost/AudioCapture.cs.
const int _audioSampleRate = 16000;
const int _audioChannelCount = 1;

/// Owns the WebSocket connection to the relay server and translates
/// between it and the rest of the app.
///
/// - Incoming BINARY messages are tagged: either a JPEG screen frame
///   (exposed via [frameStream]) or a raw PCM audio chunk (fed straight
///   into the on-device PCM audio player).
/// - Outgoing TEXT messages are input commands (mouse/keyboard) built
///   with [RemoteMessages] and sent with the send* helper methods.
///
/// This class is intentionally framework-agnostic (no BuildContext),
/// so it's easy to reuse/test. The UI layer listens to [statusStream]
/// and [frameStream] to update itself.
class RemoteService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  // A simple in-memory queue of not-yet-played audio samples. The PCM
  // player pulls from this queue via its feed callback whenever it's
  // running low, which naturally smooths out network jitter.
  final Queue<int> _audioSampleQueue = Queue<int>();
  bool _audioReady = false;
  bool _audioMuted = false;
  bool _loggedFirstAudioChunk = false;

  /// Stream of decoded JPEG frame bytes, one event per frame.
  Stream<Uint8List> get frameStream => _frameController.stream;

  /// Stream of connection status changes, so the UI can show
  /// "Connecting...", "Connected", etc.
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  ConnectionStatus get status => _status;

  bool get audioMuted => _audioMuted;

  /// Mutes/unmutes audio playback. Muting still receives audio chunks
  /// (so there's no re-sync delay when unmuting) but discards them
  /// instead of queuing them for playback.
  void setAudioMuted(bool muted) {
    _audioMuted = muted;
    if (muted) _audioSampleQueue.clear();
  }

  /// Connects to the relay server at the given address, e.g.
  /// "ws://192.168.1.42:8080", and registers this connection as the
  /// phone role. Also sets up the PCM audio player, if not already done.
  Future<void> connect(String address) async {
    await disconnect();
    await _ensureAudioSetUp();

    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(address);
      _channel = WebSocketChannel.connect(uri);

      // Send the registration message right away so the relay knows
      // to treat this socket as the phone.
      _channel!.sink.add(RemoteMessages.registerAsPhone());

      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (_) => _setStatus(ConnectionStatus.error),
        onDone: () => _setStatus(ConnectionStatus.disconnected),
      );

      _setStatus(ConnectionStatus.connected);
    } catch (_) {
      _setStatus(ConnectionStatus.error);
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _audioSampleQueue.clear();
    if (_status != ConnectionStatus.disconnected) {
      _setStatus(ConnectionStatus.disconnected);
    }
  }

  /// One-time setup of the raw-PCM audio player. Safe to call multiple
  /// times - only does real work the first time.
  Future<void> _ensureAudioSetUp() async {
    if (_audioReady) return;

    try {
      await FlutterPcmSound.setup(
        sampleRate: _audioSampleRate,
        channelCount: _audioChannelCount,
      );

      await FlutterPcmSound.setFeedThreshold(_audioSampleRate ~/ 6);
      FlutterPcmSound.setFeedCallback(_onFeedRequested);
      FlutterPcmSound.start();   // <-- ADD THIS LINE

      _audioReady = true;
    } catch (error) {
      // Audio playback isn't supported on this platform (e.g. testing in
      // a web browser instead of a real iOS/Android device), or the
      // native side failed to initialize. Print the real reason instead
      // of swallowing it, so it shows up in `flutter run`'s console -
      // video/input should keep working either way.
      // ignore: avoid_print
      print('Audio setup failed, continuing without audio: $error');
      _audioReady = false;
    }
  }

  /// Called by flutter_pcm_sound whenever it needs more samples. We pull
  /// whatever we have queued (up to a reasonable batch size); if we're
  /// running low on real audio, we pad with silence rather than
  /// stalling, since a short silent gap is far less jarring than audio
  /// glitching/stuttering.
  void _onFeedRequested(int remainingFrames) {
    const batchSize = _audioSampleRate ~/ 10; // ~100ms per feed call
    final samples = List<int>.filled(batchSize, 0);

    final available = _audioSampleQueue.length.clamp(0, batchSize);
    for (var i = 0; i < available; i++) {
      samples[i] = _audioSampleQueue.removeFirst();
    }

    FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is! List<int>) return; // Only binary messages are expected.
    if (message.isEmpty) return;

    final tag = message[0];
    final payload = Uint8List.fromList(message.sublist(1));

    if (tag == _tagVideoFrame) {
      _frameController.add(payload);
    } else if (tag == _tagAudioChunk) {
      _enqueueAudioChunk(payload);
    }
    // Unknown tags are ignored - keeps this forward-compatible.
  }

  /// Converts a chunk of little-endian 16-bit PCM bytes into individual
  /// samples and appends them to the playback queue.
  void _enqueueAudioChunk(Uint8List pcmBytes) {
    if (!_loggedFirstAudioChunk) {
      _loggedFirstAudioChunk = true;
      // ignore: avoid_print
      print('Received first audio chunk from host: ${pcmBytes.length} bytes '
          '(audioReady=$_audioReady, muted=$_audioMuted)');
    }

    if (_audioMuted || !_audioReady) return;

    final byteData = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.length ~/ 2;
    for (var i = 0; i < sampleCount; i++) {
      _audioSampleQueue.add(byteData.getInt16(i * 2, Endian.little));
    }

    // Safety cap: if the network is delivering audio faster than we can
    // play it (e.g. after a stall), drop the oldest samples rather than
    // let the queue - and therefore audio latency - grow unbounded.
    const maxQueuedSamples = _audioSampleRate * 2; // ~2 seconds
    while (_audioSampleQueue.length > maxQueuedSamples) {
      _audioSampleQueue.removeFirst();
    }
  }

  void _setStatus(ConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  // --- Outgoing input commands ---

  void sendMouseMove(double dx, double dy) => _send(RemoteMessages.mouseMove(dx, dy));

  void sendClick(String button) => _send(RemoteMessages.click(button));

  void sendScroll(double delta) => _send(RemoteMessages.scroll(delta));

  void sendText(String text) => _send(RemoteMessages.text(text));

  void sendKey(String key) => _send(RemoteMessages.key(key));

  void _send(String jsonMessage) {
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.sink.add(jsonMessage);
    }
  }

  void dispose() {
    disconnect();
    _frameController.close();
    _statusController.close();
    if (_audioReady) {
      FlutterPcmSound.release();
    }
  }
}
