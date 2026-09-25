import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

/// Logo trace loader — traces the Azaman logo while loading,
/// then resolves into the filled logo mark when complete.
///
/// Mirrors the React LogoTraceLoader component behavior:
/// - [loop]: animated stroke segment travels along the trace path
/// - [closingOutline]: full outline appears
/// - [fadingFill]: fill fades in over the outline
/// - [done]: filled logo is visible
///
/// Call [onDone] exactly once after the filled logo is visible.
class LogoTraceLoader extends StatefulWidget {
  const LogoTraceLoader({
    super.key,
    this.loading = true,
    this.isComplete = false,
    this.size = 120,
    this.strokeWidth = 4,
    this.loopDurationSeconds = 2.4,
    this.fillFadeSeconds = 0.5,
    this.color,
    this.onDone,
  });

  final bool loading;
  final bool isComplete;
  final double size;
  final double strokeWidth;
  final double loopDurationSeconds;
  final double fillFadeSeconds;
  final Color? color;
  final VoidCallback? onDone;

  @override
  State<LogoTraceLoader> createState() => _LogoTraceLoaderState();
}

enum _Phase { loop, closingOutline, fadingFill, done }

class _LogoTraceLoaderState extends State<LogoTraceLoader>
    with TickerProviderStateMixin {
  late final AnimationController _loopController;
  late final AnimationController _fillController;
  _Phase _phase = _Phase.loop;
  bool _doneCalled = false;

  static const String _viewBox = "20 20 569 553";

  static const String _tracePathData =
      "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z";

  static const List<String> _fillPathData = [
    "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z",
    "M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z",
    "M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z",
  ];

  late final Path _tracePath;
  late final List<Path> _fillPaths;
  late final double _pathLength;

  /// Convert a path made of straight L (lineto) segments into smooth cubic
  /// bezier curves using Catmull-Rom interpolation. This eliminates the
  /// polygonal/pixelated look at larger render sizes.
  Path _smoothPath(Path source) {
    final path = Path();
    final metrics = source.computeMetrics();

    for (final metric in metrics) {
      // Extract contour points by sampling along the path.
      final contour = metric.extractPath(0, metric.length);
      // Get the raw points from the contour.
      final points = <Offset>[];

      // Sample at fine intervals to get points along the path.
      const sampleCount = 80;
      for (int i = 0; i <= sampleCount; i++) {
        final t = i / sampleCount;
        final tangent = metric.getTangentForOffset(t * metric.length);
        if (tangent != null) {
          points.add(tangent.position);
        }
      }

      if (points.length < 3) {
        path.addPath(contour, Offset.zero);
        continue;
      }

      // Catmull-Rom to Bezier conversion.
      // For each segment between points[i] and points[i+1], compute control
      // points using the Catmull-Rom spline formula with tension 0.5.
      path.moveTo(points[0].dx, points[0].dy);

      for (int i = 0; i < points.length - 1; i++) {
        final p0 = i == 0 ? points[0] : points[i - 1];
        final p1 = points[i];
        final p2 = points[i + 1];
        final p3 = i + 2 < points.length ? points[i + 2] : points[i + 1];

        // Catmull-Rom to cubic bezier control points.
        final cp1 = p1 + (p2 - p0) / 6;
        final cp2 = p2 - (p3 - p1) / 6;

        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
      }

      // Close the subpath if it's closed in the original.
      path.close();
    }

    return path;
  }

  @override
  void initState() {
    super.initState();
    // Parse the raw SVG path, then smooth it.
    final rawPath = parseSvgPathData(_tracePathData);
    _tracePath = _smoothPath(rawPath);
    _fillPaths =
        _fillPathData.map((d) => _smoothPath(parseSvgPathData(d))).toList();

    final metrics = _tracePath.computeMetrics().toList();
    _pathLength = metrics.fold(0.0, (sum, m) => sum + m.length);

    _loopController = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: (widget.loopDurationSeconds * 1000).round()),
    );

    _fillController = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: (widget.fillFadeSeconds * 1000).round()),
    );

    _loopController.repeat();
    _checkPhaseTransition();
  }

  @override
  void didUpdateWidget(covariant LogoTraceLoader old) {
    super.didUpdateWidget(old);
    if (widget.loading != old.loading || widget.isComplete != old.isComplete) {
      _checkPhaseTransition();
    }
  }

  void _checkPhaseTransition() {
    final shouldComplete = widget.isComplete || !widget.loading;

    if (shouldComplete && _phase == _Phase.loop) {
      setState(() => _phase = _Phase.closingOutline);

      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _phase = _Phase.fadingFill);
        _fillController.forward().then((_) {
          if (!mounted) return;
          setState(() => _phase = _Phase.done);
          _loopController.stop();
          if (!_doneCalled && widget.onDone != null) {
            _doneCalled = true;
            widget.onDone!();
          }
        });
      });
    } else if (!shouldComplete &&
        (_phase == _Phase.done || _phase == _Phase.fadingFill)) {
      _doneCalled = false;
      _fillController.reset();
      _loopController.repeat();
      setState(() => _phase = _Phase.loop);
    }
  }

  @override
  void dispose() {
    _loopController.dispose();
    _fillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loopController, _fillController]),
        builder: (context, _) {
          return CustomPaint(
            painter: _LogoTracePainter(
              tracePath: _tracePath,
              fillPaths: _fillPaths,
              pathLength: _pathLength,
              phase: _phase,
              loopProgress: _loopController.value,
              fillProgress: _fillController.value,
              strokeWidth: widget.strokeWidth,
              color: color,
              viewBox: _viewBox,
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter that draws the logo trace animation.
class _LogoTracePainter extends CustomPainter {
  final Path tracePath;
  final List<Path> fillPaths;
  final double pathLength;
  final _Phase phase;
  final double loopProgress;
  final double fillProgress;
  final double strokeWidth;
  final Color color;
  final String viewBox;

  _LogoTracePainter({
    required this.tracePath,
    required this.fillPaths,
    required this.pathLength,
    required this.phase,
    required this.loopProgress,
    required this.fillProgress,
    required this.strokeWidth,
    required this.color,
    required this.viewBox,
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

    // Sub-pixel anti-aliasing: render at 2x then let the framework downscale.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Faint guide path.
    final guidePaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (strokeWidth / 2) / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(tracePath, guidePaint);

    if (phase == _Phase.loop) {
      _drawAnimatedTrace(canvas, paint);
    } else if (phase == _Phase.closingOutline) {
      canvas.drawPath(tracePath, paint);
    }

    if (phase == _Phase.fadingFill || phase == _Phase.done) {
      final fillOpacity = phase == _Phase.done ? 1.0 : fillProgress;
      final fillPaint = Paint()
        ..color = color.withValues(alpha: fillOpacity)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      for (final p in fillPaths) {
        canvas.drawPath(p, fillPaint);
      }
    }

    canvas.restore();
  }

  void _drawAnimatedTrace(Canvas canvas, Paint paint) {
    final segmentLength = pathLength * 0.16;
    final offset = loopProgress * pathLength;

    final metrics = tracePath.computeMetrics();
    double traveled = 0;

    for (final metric in metrics) {
      final segLen = metric.length;
      final startT = traveled;
      final endT = traveled + segLen;

      for (int i = 0; i < 2; i++) {
        final segStart = (offset + i * pathLength) % pathLength;
        final segEnd = segStart + segmentLength;

        final overlapStart = math.max(segStart, startT);
        final overlapEnd = math.min(segEnd, endT);

        if (overlapStart < overlapEnd) {
          final localStart = overlapStart - startT;
          final localEnd = overlapEnd - startT;
          final extract = metric.extractPath(localStart, localEnd);
          canvas.drawPath(extract, paint);
        }
      }

      traveled += segLen;
    }
  }

  @override
  bool shouldRepaint(covariant _LogoTracePainter old) {
    return old.phase != phase ||
        old.loopProgress != loopProgress ||
        old.fillProgress != fillProgress ||
        old.color != color ||
        old.strokeWidth != strokeWidth;
  }
}
