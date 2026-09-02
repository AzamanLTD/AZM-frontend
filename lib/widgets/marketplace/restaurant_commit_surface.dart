import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Owns the physical commit ritual for dining actions.
class RestaurantCommitSurface extends StatefulWidget {
  final Widget Function(VoidCallback onCommitted) childBuilder;
  final MarketplaceCommitStyle style;

  const RestaurantCommitSurface({super.key, required this.childBuilder, required this.style});

  @override
  State<RestaurantCommitSurface> createState() => _RestaurantCommitSurfaceState();
}

class _RestaurantCommitSurfaceState extends State<RestaurantCommitSurface> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _reducedMotionTimer;
  bool _showReducedMotion = false;
  bool _showPaperRip = false;

  void _commit() {
    if (!mounted || widget.style != MarketplaceCommitStyle.paperRip) return;
    _reducedMotionTimer?.cancel();
    if (MediaQuery.of(context).disableAnimations) {
      setState(() {
        _showReducedMotion = true;
        _showPaperRip = false;
      });
      _reducedMotionTimer = Timer(MotionTokens.celebration, () {
        if (mounted) setState(() => _showReducedMotion = false);
      });
      return;
    }
    setState(() {
      _showReducedMotion = false;
      _showPaperRip = true;
    });
    _controller.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 720))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showPaperRip = false);
        }
      });
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.childBuilder(_commit),
        if (widget.style == MarketplaceCommitStyle.paperRip)
          IgnorePointer(
            child: _showReducedMotion
                ? _reducedMotionConfirmation(duration)
                : !_showPaperRip
                    ? const SizedBox.shrink()
                    : AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final progress = _controller.value;
                          return CustomPaint(
                            key: const ValueKey('paper-rip-animation'),
                            painter: _PaperRipPainter(
                              progress: Curves.easeInOutCubic.transform(progress),
                              textColor: Theme.of(context).colorScheme.onSurface,
                            ),
                          );
                        },
                      ),
          ),
      ],
    );
  }

  Widget _reducedMotionConfirmation(Duration duration) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: duration,
        curve: MotionTokens.enter,
        builder: (_, value, child) => Transform.scale(scale: value, child: child),
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 7))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 18),
              SizedBox(width: 8),
              Text('Added to your order tray', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperRipPainter extends CustomPainter {
  final double progress;
  final Color textColor;

  const _PaperRipPainter({required this.progress, required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final targetY = size.height - 92;
    final sheetWidth = math.min(250.0, size.width - 44).toDouble();
    const sheetHeight = 82.0;
    final reveal = Curves.easeOutCubic.transform((progress / 0.42).clamp(0.0, 1.0).toDouble());
    final travel = Curves.easeInOutCubic.transform(((progress - 0.34) / 0.66).clamp(0.0, 1.0).toDouble());
    final fade = (1 - (progress - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    final startRect = Rect.fromCenter(center: Offset(centerX, size.height * 0.60), width: sheetWidth * reveal, height: sheetHeight);
    if (reveal > 0) _paintSheet(canvas, startRect, Colors.white, 1.0);
    if (travel <= 0) return;
    final from = Offset(centerX, size.height * 0.60 + sheetHeight / 2);
    final to = Offset(centerX + math.min(130.0, size.width * 0.18), targetY);
    final current = Offset.lerp(from, to, travel)!;
    final movingRect = Rect.fromCenter(center: current, width: sheetWidth * (1 - travel * 0.56), height: sheetHeight * (1 - travel * 0.38));
    final top = _jaggedHalf(movingRect, upper: true);
    final bottom = _jaggedHalf(movingRect, upper: false);
    final paper = Paint()..color = Colors.white.withValues(alpha: fade);
    canvas.drawPath(top, paper);
    canvas.drawPath(bottom, paper);
    final seam = Paint()..color = const Color(0xFFD9C7A5).withValues(alpha: fade)..strokeWidth = 1.2;
    for (var i = 0; i < 8; i++) {
      final x = movingRect.left + movingRect.width * (i + 0.5) / 8;
      final y = movingRect.center.dy + (i.isEven ? -3 : 3);
      canvas.drawCircle(Offset(x, y), 1.1, seam);
    }
    if (travel > 0.48) {
      final cartOpacity = ((travel - 0.48) / 0.52).clamp(0.0, 1.0).toDouble();
      final icon = Icons.shopping_bag_rounded;
      final textPainter = TextPainter(
        text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: 22, color: textColor.withValues(alpha: cartOpacity), fontFamily: icon.fontFamily, package: icon.fontPackage)),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(to.dx - 11, to.dy - 11));
    }
  }

  Path _jaggedHalf(Rect rect, {required bool upper}) {
    final path = Path();
    final midY = rect.center.dy;
    path.moveTo(rect.left, upper ? rect.top : midY);
    path.lineTo(rect.right, upper ? rect.top : midY);
    const points = 10;
    for (var i = points; i >= 0; i--) {
      final x = rect.left + rect.width * i / points;
      final y = midY + math.sin(i * 2.4) * 2.4 * (upper ? -1 : 1);
      path.lineTo(x, y);
    }
    path.lineTo(rect.left, upper ? midY : rect.bottom);
    path.close();
    return path;
  }

  void _paintSheet(Canvas canvas, Rect rect, Color color, double opacity) {
    final shadow = Paint()..color = const Color(0x30000000).withValues(alpha: opacity)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 5)), const Radius.circular(12)), shadow);
    final paper = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), paper);
    final fold = Paint()..color = const Color(0xFFE5D4B5).withValues(alpha: opacity);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, 5, rect.height), fold);
  }

  @override
  bool shouldRepaint(covariant _PaperRipPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.textColor != textColor;
}
