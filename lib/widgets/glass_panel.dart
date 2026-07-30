import 'dart:ui';

import 'package:flutter/material.dart';

/// A reusable "Liquid Glass" style container: a frosted, blurred,
/// semi-transparent panel with rounded corners and a soft shadow -
/// used throughout the app for status pills, control bars, and
/// settings cards.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blurSigma = 20,
    this.padding = const EdgeInsets.all(16),
    this.opacity = 0.18,
    this.glowColor,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsets padding;
  final double opacity;

  /// Optional accent color for a soft outer glow behind the panel - used
  /// to give the status pill and active controls a bit of "liquid glow".
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(opacity + 0.06),
                Colors.white.withOpacity(opacity),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.35),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withOpacity(0.35),
              blurRadius: 28,
              spreadRadius: 1,
            ),
        ],
      ),
      child: content,
    );
  }
}

/// A small pill-shaped glass badge with a continuously pulsing glow dot,
/// used for the connection status indicator ("Connected" / "Disconnected").
class GlassStatusPill extends StatefulWidget {
  const GlassStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.pulsing = true,
  });

  final String label;
  final Color color;

  /// Whether the glow dot should pulse (used for "live"/connected states)
  /// or stay static (used for disconnected/error states).
  final bool pulsing;

  @override
  State<GlassStatusPill> createState() => _GlassStatusPillState();
}

class _GlassStatusPillState extends State<GlassStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = widget.pulsing ? _controller.value : 0.0;
        return GlassPanel(
          borderRadius: 100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          glowColor: widget.color.withOpacity(0.15 + pulse * 0.15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.6 + pulse * 0.4),
                      blurRadius: 4 + pulse * 6,
                      spreadRadius: 1 + pulse * 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A round, glassy icon button used in the bottom control bar. Animates a
/// subtle scale-down + brightening glow on press for tactile feedback.
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 56,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  /// When true, the button renders with a persistent accent glow (e.g. to
  /// show "this toggle is currently on").
  final bool active;
  final Color? activeColor;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.activeColor ?? Colors.lightBlueAccent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: GlassPanel(
            borderRadius: widget.size / 2,
            padding: EdgeInsets.zero,
            opacity: widget.active ? 0.30 : 0.18,
            glowColor: (widget.active || _pressed) ? accent : null,
            child: Center(
              child: Icon(
                widget.icon,
                color: widget.active ? accent : Colors.white,
                size: widget.size * 0.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
