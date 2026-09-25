import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Wraps [child] with an animated gradient "beam" that continuously travels
/// around the border, like a comet orbiting the card's edge. Inspired by the
/// border-beam web pattern — implemented as a Flutter CustomPainter.
///
/// Performance: one CustomPainter, no images, no blur. Cheap on web.
class BorderBeam extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color beamColor;
  final double strokeWidth;
  final Duration duration;
  final bool enabled;

  const BorderBeam({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.beamColor = const Color(0xFFD4AF37), // Soft Gold — brand palette
    this.strokeWidth = 2.0,
    this.duration = const Duration(seconds: 3),
    this.enabled = true,
  });

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant BorderBeam oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _BorderBeamPainter(
                    progress: _controller.value,
                    radius: widget.borderRadius,
                    color: widget.beamColor,
                    strokeWidth: widget.strokeWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BorderBeamPainter extends CustomPainter {
  final double progress;
  final BorderRadius radius;
  final Color color;
  final double strokeWidth;

  _BorderBeamPainter({
    required this.progress,
    required this.radius,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final totalLength = metrics.length;

    const beamFraction = 0.22;
    final beamLength = totalLength * beamFraction;
    final headDistance = totalLength * progress;

    for (double i = 0; i < beamLength; i += 1.5) {
      final distance = (headDistance - i) % totalLength;
      final tangent = metrics.getTangentForOffset(distance);
      if (tangent == null) continue;
      final t = i / beamLength;
      final alpha = (1 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha * 0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        tangent.position,
        strokeWidth * (1 - t * 0.4),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BorderBeamPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
