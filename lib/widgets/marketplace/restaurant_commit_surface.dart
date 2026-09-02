import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/marketplace/experiences/marketplace_experience_blueprint.dart';
import 'package:azaman/theme/motion_tokens.dart';

typedef RestaurantCommitAction = void Function();
typedef RestaurantCommitRunner = Future<void> Function(
  RestaurantCommitAction action, {
  String? label,
  String? subtitle,
});

/// Owns the physical commit ritual for dining actions.
class RestaurantCommitSurface extends StatefulWidget {
  final Widget Function(RestaurantCommitRunner onCommit) childBuilder;
  final MarketplaceCommitStyle style;

  const RestaurantCommitSurface({super.key, required this.childBuilder, required this.style});

  @override
  State<RestaurantCommitSurface> createState() => _RestaurantCommitSurfaceState();
}

class _RestaurantCommitSurfaceState extends State<RestaurantCommitSurface> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _reducedMotionTimer;
  Timer? _commitTimer;
  bool _showReducedMotion = false;
  bool _showPaperRip = false;
  bool _commitInFlight = false;
  Offset? _lastPointerPosition;
  String? _commitLabel;
  String? _commitSubtitle;

  void _onPointerDown(PointerDownEvent event) {
    _lastPointerPosition = event.localPosition;
  }

  Future<void> _commit(
    RestaurantCommitAction action, {
    String? label,
    String? subtitle,
  }) async {
    if (!mounted || _commitInFlight) return;
    _commitInFlight = true;
    _reducedMotionTimer?.cancel();
    _commitTimer?.cancel();
    _commitLabel = label;
    _commitSubtitle = subtitle;

    if (widget.style != MarketplaceCommitStyle.paperRip) {
      action();
      _commitInFlight = false;
      return;
    }

    if (MediaQuery.of(context).disableAnimations) {
      action();
      if (!mounted) return;
      setState(() => _showReducedMotion = true);
      _reducedMotionTimer = Timer(MotionTokens.celebration, () {
        if (!mounted) return;
        setState(() => _showReducedMotion = false);
        _commitInFlight = false;
      });
      return;
    }

    setState(() {
      _showReducedMotion = false;
      _showPaperRip = true;
    });

    // The mutation boundary is time-based rather than dependent on a ticker
    // reaching an exact frame. The paper visibly peels away first, then the
    // authoritative cart mutation fires while the remaining flight continues
    // purely as presentation.
    _commitTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted || !_commitInFlight) return;
      action();
    });

    try {
      await _controller.animateTo(
        1,
        duration: const Duration(milliseconds: 720),
        curve: Curves.easeInOutCubic,
      );
    } finally {
      _commitTimer?.cancel();
      _commitTimer = null;
      if (mounted) {
        setState(() {
          _showPaperRip = false;
          _showReducedMotion = false;
        });
      }
      _commitInFlight = false;
      _commitLabel = null;
      _commitSubtitle = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _commitTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.accessibleDuration(context, MotionTokens.spatial);
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          child: widget.childBuilder(_commit),
        ),
        if (widget.style == MarketplaceCommitStyle.paperRip)
          IgnorePointer(
            child: _showReducedMotion
                ? _reducedMotionConfirmation(duration)
                : !_showPaperRip
                    ? const SizedBox.shrink()
                    : Semantics(
                        key: const ValueKey('paper-rip-item-semantics'),
                        label: _commitLabel == null
                            ? 'Item added to tray'
                            : '${_commitLabel!}${_commitSubtitle == null ? '' : ', $_commitSubtitle'}',
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final progress = _controller.value;
                            return CustomPaint(
                              key: const ValueKey('paper-rip-animation'),
                              painter: _PaperRipPainter(
                                progress: Curves.easeInOutCubic.transform(progress),
                                textColor: Theme.of(context).colorScheme.onSurface,
                                origin: _lastPointerPosition,
                                label: _commitLabel,
                                subtitle: _commitSubtitle,
                              ),
                            );
                          },
                        ),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                _commitLabel == null ? 'Added to your order tray' : '${_commitLabel} added to your tray',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
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
  final Offset? origin;
  final String? label;
  final String? subtitle;

  const _PaperRipPainter({
    required this.progress,
    required this.textColor,
    required this.origin,
    this.label,
    this.subtitle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final originPoint = origin ?? Offset(size.width / 2, size.height * 0.60);
    final targetY = size.height - 92;
    final target = Offset(originPoint.dx.clamp(24.0, size.width - 24.0).toDouble(), targetY);
    final sheetWidth = math.min(250.0, size.width - 44).toDouble();
    const sheetHeight = 82.0;
    final reveal = Curves.easeOutCubic.transform((progress / 0.42).clamp(0.0, 1.0).toDouble());
    final travel = Curves.easeInOutCubic.transform(((progress - 0.34) / 0.66).clamp(0.0, 1.0).toDouble());
    final fade = (1 - (progress - 0.55) / 0.45).clamp(0.0, 1.0).toDouble();
    final startCenter = Offset(
      originPoint.dx.clamp(sheetWidth / 2 + 10, size.width - sheetWidth / 2 - 10).toDouble(),
      originPoint.dy.clamp(sheetHeight / 2 + 10, size.height - sheetHeight / 2 - 30).toDouble(),
    );
    final startRect = Rect.fromCenter(center: startCenter, width: sheetWidth * reveal, height: sheetHeight);
    if (reveal > 0) _paintSheet(canvas, startRect, Colors.white, 1.0);
    if (travel <= 0) return;
    final from = Offset(startCenter.dx, startCenter.dy + sheetHeight / 2);
    final current = Offset.lerp(from, target, travel)!;
    final movingRect = Rect.fromCenter(
      center: current,
      width: sheetWidth * (1 - travel * 0.56),
      height: sheetHeight * (1 - travel * 0.38),
    );
    final top = _jaggedHalf(movingRect, upper: true);
    final bottom = _jaggedHalf(movingRect, upper: false);
    final paper = Paint()..color = Colors.white.withValues(alpha: fade);
    canvas.drawPath(top, paper);
    canvas.drawPath(bottom, paper);
    _paintItemText(canvas, movingRect, fade);
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
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 22,
            color: textColor.withValues(alpha: cartOpacity),
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(target.dx - 11, target.dy - 11));
    }
  }

  void _paintItemText(Canvas canvas, Rect rect, double opacity) {
    if (label == null || rect.width < 70) return;
    final maxWidth = math.max(40.0, rect.width - 26);
    final title = TextPainter(
      text: TextSpan(
        text: label!,
        style: TextStyle(color: const Color(0xFF2D2416).withValues(alpha: opacity), fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    title.paint(canvas, Offset(rect.left + 13, rect.top + 13));
    if (subtitle == null || rect.height < 42) return;
    final detail = TextPainter(
      text: TextSpan(
        text: subtitle!,
        style: TextStyle(color: const Color(0xFF8B7A5A).withValues(alpha: opacity), fontSize: 8.5, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    detail.paint(canvas, Offset(rect.left + 13, rect.top + 31));
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
    _paintItemText(canvas, rect, opacity);
  }

  @override
  bool shouldRepaint(covariant _PaperRipPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.textColor != textColor ||
      oldDelegate.origin != origin ||
      oldDelegate.label != label ||
      oldDelegate.subtitle != subtitle;
}