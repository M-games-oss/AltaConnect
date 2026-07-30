import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/remote_service.dart';
import '../widgets/glass_panel.dart';
import '../widgets/touchpad_area.dart';
import 'settings_screen.dart';

/// The main (and only, besides Settings) screen of the app. Shows the
/// live desktop stream and layers a [TouchpadArea] on top of it to
/// turn touches into mouse/keyboard commands sent to the PC.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RemoteService _remoteService = RemoteService();

  // The hidden text field is a well-known trick for driving the
  // system on-screen keyboard without building a custom one. We keep
  // its content pinned to a single sentinel space character so we can
  // reliably detect both "typed a character" (text got longer) and
  // "pressed backspace" (text got shorter/emptied) - see
  // `_handleKeyboardInput` below for details.
  final TextEditingController _keyboardController = TextEditingController(text: ' ');
  final FocusNode _keyboardFocusNode = FocusNode();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  Uint8List? _latestFrame;
  bool _keyboardVisible = false;
  bool _audioMuted = false;

  @override
  void initState() {
    super.initState();
    _remoteService.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    _remoteService.frameStream.listen((frame) {
      if (mounted) setState(() => _latestFrame = frame);
    });
    _connectUsingSavedAddress();
  }

  Future<void> _connectUsingSavedAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(kServerAddressPrefKey) ?? kDefaultServerAddress;
    await _remoteService.connect(address);
  }

  @override
  void dispose() {
    _remoteService.dispose();
    _keyboardController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _toggleKeyboard() {
    setState(() => _keyboardVisible = !_keyboardVisible);
    if (_keyboardVisible) {
      _keyboardController.text = ' ';
      _keyboardFocusNode.requestFocus();
    } else {
      _keyboardFocusNode.unfocus();
    }
  }

  /// See the comment on `_keyboardController` above for why we keep a
  /// single sentinel space character in the field at all times.
  void _handleKeyboardInput(String newValue) {
    if (newValue.length > 1) {
      // Characters were typed after the sentinel - forward them, then
      // reset back to just the sentinel.
      final typedChars = newValue.substring(1);
      _remoteService.sendText(typedChars);
      _keyboardController.text = ' ';
      _keyboardController.selection =
          TextSelection.collapsed(offset: _keyboardController.text.length);
    } else if (newValue.isEmpty) {
      // The sentinel itself was deleted - that's a backspace press.
      _remoteService.sendKey('backspace');
      _keyboardController.text = ' ';
      _keyboardController.selection =
          TextSelection.collapsed(offset: _keyboardController.text.length);
    }
  }

  Color get _statusColor {
    switch (_status) {
      case ConnectionStatus.connected:
        return Colors.greenAccent;
      case ConnectionStatus.connecting:
        return Colors.orangeAccent;
      case ConnectionStatus.error:
        return Colors.redAccent;
      case ConnectionStatus.disconnected:
        return Colors.grey;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting…';
      case ConnectionStatus.error:
        return 'Connection error';
      case ConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: SafeArea(
        child: Stack(
          children: [
            // --- Desktop preview + touch input surface ---
            Positioned.fill(
              child: TouchpadArea(
                onMouseMove: _remoteService.sendMouseMove,
                onLeftClick: () => _remoteService.sendClick('left'),
                onRightClick: () => _remoteService.sendClick('right'),
                onScroll: _remoteService.sendScroll,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  margin: const EdgeInsets.fromLTRB(12, 64, 12, 96),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black,
                    border: Border.all(
                      color: _statusColor.withOpacity(
                        _status == ConnectionStatus.connected ? 0.5 : 0.15,
                      ),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                      if (_status == ConnectionStatus.connected)
                        BoxShadow(
                          color: _statusColor.withOpacity(0.25),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildPreview(),
                ),
              ),
            ),

            // --- Hidden text field that drives the system keyboard ---
            if (_keyboardVisible)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Opacity(
                  opacity: 0.0,
                  child: TextField(
                    controller: _keyboardController,
                    focusNode: _keyboardFocusNode,
                    onChanged: _handleKeyboardInput,
                    autofocus: true,
                  ),
                ),
              ),

            // --- Top status pill ---
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GlassStatusPill(
                  label: _statusLabel,
                  color: _statusColor,
                  pulsing: _status == ConnectionStatus.connected,
                ),
              ),
            ),

            // --- Bottom control bar ---
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassIconButton(
                    icon: Icons.keyboard_alt_outlined,
                    onTap: _toggleKeyboard,
                  ),
                  const SizedBox(width: 20),
                  GlassIconButton(
                    icon: _audioMuted ? Icons.volume_off : Icons.volume_up,
                    active: _audioMuted,
                    activeColor: Colors.redAccent,
                    onTap: () {
                      setState(() => _audioMuted = !_audioMuted);
                      _remoteService.setAudioMuted(_audioMuted);
                    },
                  ),
                  const SizedBox(width: 20),
                  GlassIconButton(
                    icon: _status == ConnectionStatus.connected
                        ? Icons.link_off
                        : Icons.link,
                    active: _status == ConnectionStatus.connected,
                    activeColor: Colors.greenAccent,
                    onTap: () async {
                      if (_status == ConnectionStatus.connected) {
                        await _remoteService.disconnect();
                      } else {
                        await _connectUsingSavedAddress();
                      }
                    },
                  ),
                  const SizedBox(width: 20),
                  GlassIconButton(
                    icon: Icons.settings_outlined,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                      // Address may have changed - reconnect with the new one.
                      await _connectUsingSavedAddress();
                    },
                  ),
                ],
              ),
            ),

            // --- Quick-access row for Enter / Space, shown with keyboard ---
            if (_keyboardVisible)
              Positioned(
                bottom: 88,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _quickKeyButton('Space', () => _remoteService.sendKey('space')),
                    const SizedBox(width: 12),
                    _quickKeyButton('Enter', () => _remoteService.sendKey('enter')),
                    const SizedBox(width: 12),
                    _quickKeyButton('Tab', () => _remoteService.sendKey('tab')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quickKeyButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: GlassPanel(
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    );
  }

  Widget _buildPreview() {
    if (_latestFrame == null) {
      return const Center(
        child: Text(
          'Waiting for the desktop stream…',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Image.memory(
      _latestFrame!,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
