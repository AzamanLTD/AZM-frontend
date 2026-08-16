import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A small cluster of dots that orbit and pulse, signaling "AI is thinking".
/// Inspired by the general "AI/agent status indicator" pattern — dotted orb
/// loaders signal AI-driven processing without implying deterministic progress.
class ThinkingOrb extends StatefulWidget {
  final double size;
  final Color color;
  final int dotCount;

  const ThinkingOrb({
    super.key,
    this.size = 22,
    this.color = const Color(0xFFD4AF37),
    this.dotCount = 4,
  });

  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ThinkingOrbPainter(
            t: _controller.value,
            color: widget.color,
            dotCount: widget.dotCount,
          ),
        ),
      ),
    );
  }
}

class _ThinkingOrbPainter extends CustomPainter {
  final double t;
  final Color color;
  final int dotCount;

  _ThinkingOrbPainter({
    required this.t,
    required this.color,
    required this.dotCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final orbitRadius = size.width * 0.32;

    for (int i = 0; i < dotCount; i++) {
      final phaseOffset = i / dotCount;
      final angle = (t + phaseOffset) * 2 * math.pi;
      final pulsePhase = ((t * 2) + phaseOffset) % 1.0;
      final pulse = 0.5 + 0.5 * (1 - (pulsePhase - 0.5).abs() * 2);

      final dotCenter = Offset(
        center.dx + orbitRadius * math.cos(angle),
        center.dy + orbitRadius * math.sin(angle),
      );
      final dotRadius = size.width * 0.09 * (0.6 + 0.4 * pulse);

      canvas.drawCircle(
        dotCenter,
        dotRadius,
        Paint()..color = color.withValues(alpha: 0.4 + 0.6 * pulse),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThinkingOrbPainter oldDelegate) =>
      oldDelegate.t != t;
}
