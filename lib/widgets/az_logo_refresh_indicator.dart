// =============================================================================
// AZAMAN — Custom Pull-to-Refresh with Logo Trace Animation
//
// Replaces the default Material circular indicator with a mini version
// of the Azaman logo that has a line tracing around its outline while
// refreshing. The same animation style as the splash-screen LogoTraceLoader,
// scaled down for in-list use.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

/// A pull-to-refresh indicator that shows a mini logo with a tracing line
/// animation instead of the default circular spinner.
///
/// Drop-in replacement for `AzPullToRefresh` — same API (`child` + `onRefresh`).
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
  // Pull tracking
  double _dragOffset = 0; // current pull distance in px (0 = rest)
  static const double _triggerDistance = 72; // pull needed to trigger refresh
  static const double _maxDrag = 110; // visual cap to prevent pulling too far

  // Refresh state
  bool _isRefreshing = false;

  // Animation for the tracing line
  late final AnimationController _traceController;

  @override
  void initState() {
    super.initState();
    _traceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _traceController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isRefreshing) return false;

    if (notification is ScrollStartNotification) {
      // Reset on new scroll if at top
      if (notification.metrics.pixels <= 0) {
        _dragOffset = 0;
      }
    } else if (notification is OverscrollNotification) {
      // Accumulate overscroll (pulling down at the top of the list)
      if (notification.overscroll < 0 && notification.metrics.pixels <= 0) {
        // Negative overscroll = pulling down at the top
        _dragOffset += (-notification.overscroll) * 0.5; // damped
        if (_dragOffset > _maxDrag) _dragOffset = _maxDrag;
        setState(() {});
      }
    } else if (notification is ScrollEndNotification) {
      if (_dragOffset >= _triggerDistance && !_isRefreshing) {
        _triggerRefresh();
      } else if (!_isRefreshing) {
        // Snap back
        setState(() => _dragOffset = 0);
      }
    }
    return false;
  }

  Future<void> _triggerRefresh() async {
    setState(() {
      _isRefreshing = true;
      _dragOffset = _triggerDistance;
    });
    _traceController.repeat();

    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        _traceController.stop();
        setState(() {
          _isRefreshing = false;
          _dragOffset = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Stack(
        children: [
          // The child content, pushed down by the drag offset
          Transform.translate(
            offset: Offset(0, _isRefreshing ? _triggerDistance : _dragOffset),
            child: widget.child,
          ),
          // The refresh indicator at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _isRefreshing ? _triggerDistance : _dragOffset,
            child: ClipRect(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: (_dragOffset / _triggerDistance).clamp(0.0, 1.0),
                    child: _MiniLogoTrace(
                      size: 36,
                      traceAnimation: _traceController,
                      color: colors.accent,
                      isRefreshing: _isRefreshing,
                      pullProgress:
                          (_dragOffset / _triggerDistance).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini version of the logo trace — shows the Azaman logo outline with a
/// line tracing around it. During pull, the guide path fades in. During
/// refresh, the animated tracing segment loops.
class _MiniLogoTrace extends StatelessWidget {
  final double size;
  final Animation<double> traceAnimation;
  final Color color;
  final bool isRefreshing;
  final double pullProgress;

  const _MiniLogoTrace({
    required this.size,
    required this.traceAnimation,
    required this.color,
    required this.isRefreshing,
    required this.pullProgress,
  });

  // Same viewBox and path data as LogoTraceLoader
  static const String _viewBox = "20 20 569 553";

  static const String _tracePathData =
      "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z";

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: traceAnimation,
        builder: (context, _) {
          return CustomPaint(
            painter: _MiniLogoTracePainter(
              tracePathData: _tracePathData,
              loopProgress: isRefreshing ? traceAnimation.value : 0,
              isRefreshing: isRefreshing,
              pullProgress: pullProgress,
              color: color,
              viewBox: _viewBox,
              strokeWidth: 5,
            ),
          );
        },
      ),
    );
  }
}

class _MiniLogoTracePainter extends CustomPainter {
  final String tracePathData;
  final double loopProgress;
  final bool isRefreshing;
  final double pullProgress;
  final Color color;
  final String viewBox;
  final double strokeWidth;

  _MiniLogoTracePainter({
    required this.tracePathData,
    required this.loopProgress,
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

    final scaleX = size.width / vbW;
    final scaleY = size.height / vbH;
    final scale = math.min(scaleX, scaleY);

    final dx = (size.width - vbW * scale) / 2 - vbX * scale;
    final dy = (size.height - vbH * scale) / 2 - vbY * scale;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    // Parse the path
    final tracePath = _parsePath(tracePathData);

    // Faint guide path — visible during pull and refresh
    final guideOpacity = isRefreshing ? 0.25 : (pullProgress * 0.25);
    final guidePaint = Paint()
      ..color = color.withValues(alpha: guideOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (strokeWidth / 2) / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(tracePath, guidePaint);

    if (isRefreshing) {
      // Animated tracing segment — same technique as LogoTraceLoader
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth / scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      _drawAnimatedTrace(canvas, tracePath, paint);
    }

    canvas.restore();
  }

  void _drawAnimatedTrace(Canvas canvas, Path tracePath, Paint paint) {
    final metrics = tracePath.computeMetrics();
    double totalLength = 0;
    for (final m in metrics) {
      totalLength += m.length;
    }

    final segmentLength = totalLength * 0.18;
    final offset = loopProgress * totalLength;

    double traveled = 0;
    for (final metric in metrics) {
      final segLen = metric.length;

      for (int i = 0; i < 2; i++) {
        final segStart = (offset + i * totalLength) % totalLength;
        final segEnd = segStart + segmentLength;

        final overlapStart = math.max(segStart, traveled);
        final overlapEnd = math.min(segEnd, traveled + segLen);

        if (overlapStart < overlapEnd) {
          final localStart = overlapStart - traveled;
          final localEnd = overlapEnd - traveled;
          final extract = metric.extractPath(localStart, localEnd);
          canvas.drawPath(extract, paint);
        }
      }

      traveled += segLen;
    }
  }

  @override
  bool shouldRepaint(covariant _MiniLogoTracePainter old) {
    return old.loopProgress != loopProgress ||
        old.isRefreshing != isRefreshing ||
        old.pullProgress != pullProgress ||
        old.color != color;
  }
}

/// Parse SVG path data string into a Path object.
/// Minimal parser for the Azaman logo path (only M, L, Z commands).
Path _parsePath(String data) {
  final path = Path();
  final commands = data.split(RegExp(r'(?=[MLZ])'));
  double currentX = 0, currentY = 0;

  for (final cmd in commands) {
    if (cmd.isEmpty) continue;
    final letter = cmd[0];
    final args = cmd
        .substring(1)
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.parse)
        .toList();

    switch (letter) {
      case 'M':
        currentX = args[0];
        currentY = args[1];
        path.moveTo(currentX, currentY);
        for (int i = 2; i < args.length; i += 2) {
          currentX = args[i];
          currentY = args[i + 1];
          path.lineTo(currentX, currentY);
        }
        break;
      case 'L':
        for (int i = 0; i < args.length; i += 2) {
          currentX = args[i];
          currentY = args[i + 1];
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
