import 'dart:async';
import 'package:flutter/material.dart';

/// A full-screen "touchpad" surface layered on top of the desktop
/// preview image. It interprets raw touch input the same way a
/// laptop trackpad does:
///
///   - One finger, drag         -> relative mouse movement
///   - One finger, quick tap    -> left click
///   - One finger, press & hold -> right click
///   - Two fingers, drag        -> scroll
///
/// We use the low-level [Listener] widget (raw pointer events) instead
/// of a [GestureDetector] because we need to manually decide, at
/// runtime, whether an in-progress gesture is a drag, a tap, a long
/// press, or a two-finger scroll - based on how many fingers are down
/// and how far they've moved. A single GestureDetector can't express
/// this multi-finger branching logic.
///
/// It also renders a brief, fading "ripple" circle at each tap/click
/// point purely for visual feedback, since there's no real on-screen
/// cursor to show the user where their input landed.
class TouchpadArea extends StatefulWidget {
  const TouchpadArea({
    super.key,
    required this.child,
    required this.onMouseMove,
    required this.onLeftClick,
    required this.onRightClick,
    required this.onScroll,
    this.moveSensitivity = 1.4,
    this.scrollSensitivity = 0.6,
  });

  final Widget child;
  final void Function(double dx, double dy) onMouseMove;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;
  final void Function(double delta) onScroll;
  final double moveSensitivity;
  final double scrollSensitivity;

  @override
  State<TouchpadArea> createState() => _TouchpadAreaState();
}

class _Ripple {
  _Ripple(this.position, this.controller, this.color);
  final Offset position;
  final AnimationController controller;
  final Color color;
}

class _TouchpadAreaState extends State<TouchpadArea> with TickerProviderStateMixin {
  final Map<int, Offset> _activePointers = {};
  final List<_Ripple> _ripples = [];

  Offset? _lastTwoFingerFocalPoint;
  Timer? _longPressTimer;
  bool _movedBeyondTapThreshold = false;
  DateTime? _firstPointerDownTime;
  Offset? _firstPointerDownPosition;

  static const double _tapMoveThreshold = 8.0; // logical pixels
  static const Duration _longPressDuration = Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          widget.child,
          ..._ripples.map(_buildRippleWidget),
        ],
      ),
    );
  }

  Widget _buildRippleWidget(_Ripple ripple) {
    return AnimatedBuilder(
      animation: ripple.controller,
      builder: (context, _) {
        final progress = ripple.controller.value;
        const maxRadius = 36.0;
        final radius = maxRadius * progress;
        final opacity = (1.0 - progress).clamp(0.0, 1.0);

        return Positioned(
          left: ripple.position.dx - radius,
          top: ripple.position.dy - radius,
          child: IgnorePointer(
            child: Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ripple.color.withOpacity(opacity * 0.8),
                  width: 2,
                ),
                color: ripple.color.withOpacity(opacity * 0.12),
              ),
            ),
          ),
        );
      },
    );
  }

  void _spawnRipple(Offset position, Color color) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    final ripple = _Ripple(position, controller, color);
    setState(() => _ripples.add(ripple));

    controller.forward().whenComplete(() {
      setState(() => _ripples.remove(ripple));
      controller.dispose();
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      // Start of a brand-new gesture: reset tracking state and start
      // the long-press timer. If the finger lifts quickly without
      // much movement, this becomes a tap (left click). If it's still
      // down after `_longPressDuration` without moving, it's a right
      // click. If it moves a lot, it's a drag (mouse move).
      _movedBeyondTapThreshold = false;
      _firstPointerDownTime = DateTime.now();
      _firstPointerDownPosition = event.localPosition;

      _longPressTimer?.cancel();
      _longPressTimer = Timer(_longPressDuration, () {
        if (_activePointers.length == 1 && !_movedBeyondTapThreshold) {
          widget.onRightClick();
          _spawnRipple(event.localPosition, Colors.orangeAccent);
          // Prevent this same gesture from also firing a tap on release.
          _movedBeyondTapThreshold = true;
        }
      });
    } else if (_activePointers.length == 2) {
      // A second finger just touched down: this is now a two-finger
      // scroll gesture, not a click/drag. Cancel any pending long
      // press and record the starting focal point for delta tracking.
      _longPressTimer?.cancel();
      _movedBeyondTapThreshold = true;
      _lastTwoFingerFocalPoint = _averageOfActivePointers();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;

    if (_activePointers.length == 1) {
      final delta = event.delta;
      if (delta.distance > 0) {
        if (delta.distance > 1.0) _movedBeyondTapThreshold = true;
        widget.onMouseMove(
          delta.dx * widget.moveSensitivity,
          delta.dy * widget.moveSensitivity,
        );
      }
    } else if (_activePointers.length == 2) {
      final focal = _averageOfActivePointers();
      if (_lastTwoFingerFocalPoint != null) {
        final dy = focal.dy - _lastTwoFingerFocalPoint!.dy;
        if (dy.abs() > 0.5) {
          widget.onScroll(-dy * widget.scrollSensitivity);
        }
      }
      _lastTwoFingerFocalPoint = focal;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final wasSingleFingerGesture = _activePointers.length == 1;
    _activePointers.remove(event.pointer);

    if (wasSingleFingerGesture) {
      _longPressTimer?.cancel();

      final elapsed = _firstPointerDownTime == null
          ? Duration.zero
          : DateTime.now().difference(_firstPointerDownTime!);

      // Only treat this as a tap (left click) if the finger didn't
      // move much and wasn't held long enough to already have
      // triggered the long-press right click above.
      if (!_movedBeyondTapThreshold && elapsed < _longPressDuration) {
        widget.onLeftClick();
        _spawnRipple(_firstPointerDownPosition ?? event.localPosition, Colors.white);
      }
    }

    if (_activePointers.length < 2) {
      _lastTwoFingerFocalPoint = null;
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _longPressTimer?.cancel();
    _lastTwoFingerFocalPoint = null;
  }

  Offset _averageOfActivePointers() {
    final positions = _activePointers.values.toList();
    final dx = positions.map((p) => p.dx).reduce((a, b) => a + b) / positions.length;
    final dy = positions.map((p) => p.dy).reduce((a, b) => a + b) / positions.length;
    return Offset(dx, dy);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    for (final ripple in _ripples) {
      ripple.controller.dispose();
    }
    super.dispose();
  }
}
