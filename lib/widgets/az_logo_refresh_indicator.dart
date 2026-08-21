// =============================================================================
// AZAMAN — Bounce-Reveal Pull-to-Refresh with Logo Trace Animation
//
// The indicator sits BEHIND the scroll content. When the user pulls down,
// BouncingScrollPhysics moves the content down, revealing the logo in the
// gap. On release past the trigger distance, the content is held down
// (Transform.translate) while the logo's tracer loop animates. When
// refresh completes, the content slides back up, covering the logo.
//
// For scroll views that use ClampingScrollPhysics (overscroll), we
// mimic the bounce by translating the content manually.
//
// The logo: three-part Azaman logo that traces all 3 SVG subpaths in
// solid black as the user pulls. On release, a moving tracer segment
// loops around all 3 parts to indicate loading.
// =============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class AzLogoRefreshIndicator extends ConsumerStatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  const AzLogoRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  ConsumerState<AzLogoRefreshIndicator> createState() =>
      _AzLogoRefreshIndicatorState();
}

class _AzLogoRefreshIndicatorState
    extends ConsumerState<AzLogoRefreshIndicator>
    with TickerProviderStateMixin {
  double _pullOffset = 0;
  static const double _triggerDistance = 70;
  static const double _maxDrag = 110;
  static const double _indicatorSize = 28;
  static const double _platePad = 6.0;
  static const double _plateRadius = 12.0;
  static const Duration _minDisplayTime = Duration(milliseconds: 1800);

  bool _isRefreshing = false;
  bool _isDragging = false;
  bool _isBouncing = false; // true when BouncingScrollPhysics is active

  late final AnimationController _traceController;
  late final AnimationController _fadeController;
  late final AnimationController _slideController; // refresh content slide

  @override
  void initState() {
    super.initState();
    _traceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _traceController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollStartNotification) {
      if (notification.metrics.pixels <= 0) {
        _pullOffset = 0;
        _isDragging = true;
      }
    } else if (notification is OverscrollNotification) {
      // ClampingScrollPhysics fallback — content doesn't bounce
      _isBouncing = false;
      if (notification.overscroll < 0 && notification.metrics.pixels <= 0) {
        _pullOffset += (-notification.overscroll) * 0.5;
        if (_pullOffset > _maxDrag) _pullOffset = _maxDrag;
        setState(() {});
      }
    } else if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels < 0 && _isDragging) {
        // BouncingScrollPhysics — content is at negative position
        _isBouncing = true;
        _pullOffset = (-notification.metrics.pixels) * 0.75;
        if (_pullOffset > _maxDrag) _pullOffset = _maxDrag;
        setState(() {});
      } else if (notification.metrics.pixels >= 0 && _isDragging && !_isBouncing) {
        // Overscroll bouncing back to 0
        if (_pullOffset > 0) {
          _pullOffset = 0;
          setState(() {});
        }
      }
    } else if (notification is ScrollEndNotification) {
      _isDragging = false;
      if (_pullOffset >= _triggerDistance && !_isRefreshing) {
        _triggerRefresh();
      } else if (!_isRefreshing) {
        setState(() => _pullOffset = 0);
      }
    }
    return false;
  }

  Future<void> _triggerRefresh() async {
    setState(() {
      _isRefreshing = true;
      _pullOffset = _triggerDistance;
    });
    // Slide content down to keep indicator visible after bounce settles
    _slideController.forward(from: 0);
    _fadeController.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 350));
    _traceController.repeat();
    try {
      await Future.wait([
        widget.onRefresh(),
        Future.delayed(_minDisplayTime),
      ]);
    } finally {
      if (mounted) {
        _traceController.stop();
        _fadeController.reverse();
        _slideController.reverse();
        await Future.delayed(const Duration(milliseconds: 320));
        if (mounted) {
          setState(() {
            _isRefreshing = false;
            _pullOffset = 0;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final indicatorColor = colors.textPrimary;
    final pullProgress = (_pullOffset / _triggerDistance).clamp(0.0, 1.0);
    final plateSize = _indicatorSize + _platePad * 2;

    // Content translation:
    // - Bounce: content already moves via scroll physics → no translate
    // - Overscroll: translate to mimic bounce
    // - Refresh: translate by triggerDistance (animated)
    double contentTranslate;
    if (_isRefreshing) {
      contentTranslate = Curves.easeOutCubic.transform(_slideController.value) * _triggerDistance;
    } else if (_isBouncing) {
      contentTranslate = 0;
    } else {
      contentTranslate = _pullOffset;
    }

    // Indicator opacity
    double indicatorOpacity;
    if (_isRefreshing) {
      indicatorOpacity = 1.0;
    } else {
      indicatorOpacity = (pullProgress * 0.9 + 0.1).clamp(0.0, 1.0);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          // ── Indicator BEHIND content ──────────────────────────────
          // Always rendered; opacity controls visibility. The content
          // bouncing down (or being translated) reveals it in the gap.
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: indicatorOpacity,
                child: Center(
                  child: Container(
                    width: plateSize,
                    height: plateSize,
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(_plateRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _ThreePartLogoTrace(
                        size: _indicatorSize,
                        traceAnimation: _traceController,
                        fadeAnimation: _fadeController,
                        color: indicatorColor,
                        isRefreshing: _isRefreshing,
                        pullProgress: pullProgress,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── Content ON TOP, translated when needed ────────────────
          Transform.translate(
            offset: Offset(0, contentTranslate),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Three-Part Logo Trace Widget (unchanged)
// =============================================================================

class _ThreePartLogoTrace extends StatelessWidget {
  final double size;
  final Animation<double> traceAnimation;
  final Animation<double> fadeAnimation;
  final Color color;
  final bool isRefreshing;
  final double pullProgress;

  const _ThreePartLogoTrace({
    required this.size,
    required this.traceAnimation,
    required this.fadeAnimation,
    required this.color,
    required this.isRefreshing,
    required this.pullProgress,
  });

  static const String _viewBox = "20 20 569 553";

  static const String _part1 =
      "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z";
  static const String _part2 =
      "M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z";
  static const String _part3 =
      "M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z";

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: Listenable.merge([traceAnimation, fadeAnimation]),
        builder: (context, _) {
          return CustomPaint(
            painter: _ThreePartLogoPainter(
              partPaths: [_parsePath(_part1), _parsePath(_part2), _parsePath(_part3)],
              loopProgress: isRefreshing ? traceAnimation.value : 0,
              fadeProgress: fadeAnimation.value,
              isRefreshing: isRefreshing,
              pullProgress: pullProgress,
              color: color,
              viewBox: _viewBox,
              strokeWidth: 1.8,
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Three-Part Logo Painter (unchanged)
// =============================================================================

class _ThreePartLogoPainter extends CustomPainter {
  final List<Path> partPaths;
  final double loopProgress;
  final double fadeProgress;
  final bool isRefreshing;
  final double pullProgress;
  final Color color;
  final String viewBox;
  final double strokeWidth;

  _ThreePartLogoPainter({
    required this.partPaths,
    required this.loopProgress,
    required this.fadeProgress,
    required this.isRefreshing,
    required this.pullProgress,
    required this.color,
    required this.viewBox,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final parts = viewBox.split(' ');
    final vbX = double.parse(parts[0]);
    final vbY = double.parse(parts[1]);
    final vbW = double.parse(parts[2]);
    final vbH = double.parse(parts[3]);
    final scale = math.min(size.width / vbW, size.height / vbH);
    final dx = (size.width - vbW * scale) / 2 - vbX * scale;
    final dy = (size.height - vbH * scale) / 2 - vbY * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final guideOpacity = isRefreshing ? 0.15 : (pullProgress * 0.12 + 0.03);
    final guidePaint = Paint()
      ..color = color.withValues(alpha: guideOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (strokeWidth * 0.6) / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final p in partPaths) {
      canvas.drawPath(p, guidePaint);
    }

    if (isRefreshing) {
      final outlineOpacity = (1.0 - fadeProgress * 0.8).clamp(0.2, 1.0);
      final outlinePaint = Paint()
        ..color = color.withValues(alpha: outlineOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      for (final p in partPaths) {
        canvas.drawPath(p, outlinePaint);
      }

      final tracerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (strokeWidth * 1.4) / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      _drawMovingTracer(canvas, partPaths, tracerPaint, loopProgress);

    } else if (pullProgress > 0) {
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      for (final p in partPaths) {
        _drawSubpathProgress(canvas, p, fillPaint, pullProgress);
      }
    }

    canvas.restore();
  }

  void _drawSubpathProgress(Canvas canvas, Path path, Paint paint, double progress) {
    if (progress <= 0) return;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final targetLen = metric.length * progress;
      if (targetLen <= 0) continue;
      canvas.drawPath(metric.extractPath(0, targetLen.clamp(0, metric.length)), paint);
    }
  }

  void _drawMovingTracer(Canvas canvas, List<Path> paths, Paint paint, double loopProgress) {
    final allMetrics = <ui.PathMetric>[];
    double totalLength = 0;
    for (final p in paths) {
      for (final m in p.computeMetrics()) {
        allMetrics.add(m);
        totalLength += m.length;
      }
    }
    if (totalLength <= 0) return;

    final segmentLength = totalLength * 0.18;
    final startPos = loopProgress * totalLength;

    for (int pass = 0; pass < 2; pass++) {
      final segStart = (startPos + pass * totalLength) % totalLength;
      final segEnd = segStart + segmentLength;

      double traveled = 0;
      for (final metric in allMetrics) {
        final metricEnd = traveled + metric.length;
        final overlapStart = math.max(segStart, traveled);
        final overlapEnd = math.min(segEnd, metricEnd);
        if (overlapStart < overlapEnd) {
          final localStart = overlapStart - traveled;
          final localEnd = overlapEnd - traveled;
          canvas.drawPath(
            metric.extractPath(localStart.clamp(0, metric.length), localEnd.clamp(0, metric.length)),
            paint,
          );
        }
        if (segEnd > totalLength) {
          final wrapEnd = segEnd - totalLength;
          final wrapStart = math.max(0, traveled);
          final wrapOverlapEnd = math.min(wrapEnd, metricEnd);
          if (wrapStart < wrapOverlapEnd) {
            final localStart = wrapStart - traveled;
            final localEnd = wrapOverlapEnd - traveled;
            canvas.drawPath(
              metric.extractPath(localStart.clamp(0, metric.length), localEnd.clamp(0, metric.length)),
              paint,
            );
          }
        }
        traveled = metricEnd;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThreePartLogoPainter old) {
    return old.loopProgress != loopProgress ||
        old.fadeProgress != fadeProgress ||
        old.isRefreshing != isRefreshing ||
        old.pullProgress != pullProgress ||
        old.color != color;
  }
}

Path _parsePath(String data) {
  final path = Path();
  final commands = data.split(RegExp(r'(?=[MLZ])'));
  double currentX = 0, currentY = 0;
  for (final cmd in commands) {
    if (cmd.isEmpty) continue;
    final letter = cmd[0];
    final args = cmd.substring(1).trim().split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty).map(double.parse).toList();
    switch (letter) {
      case 'M':
        currentX = args[0]; currentY = args[1];
        path.moveTo(currentX, currentY);
        for (int i = 2; i < args.length; i += 2) {
          currentX = args[i]; currentY = args[i + 1];
          path.lineTo(currentX, currentY);
        }
        break;
      case 'L':
        for (int i = 0; i < args.length; i += 2) {
          currentX = args[i]; currentY = args[i + 1];
          path.lineTo(currentX, currentY);
        }
        break;
      case 'Z':
        path.close();
        break;
    }
  }
  return path;
}
