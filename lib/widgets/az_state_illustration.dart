// lib/widgets/az_state_illustration.dart
// =============================================================================
// AZ STATE ILLUSTRATION  (TASK-023)
//
// A drawn state, not an icon in a circle. Five scenes, all vector, all painted
// from the live theme so they re-tint with accents and both brightnesses.
//
// Why draw instead of ship PNGs: the app already refuses the asset pipeline for
// anything that must tint perfectly (see the seat-canvas painter). A drawing
// costs nothing at every density, and it can draw itself on entry.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/providers/theme_provider.dart';

enum AzStateScene { emptyBox, offline, error, search, receipt }

class AzStateIllustration extends StatelessWidget {
  final AzStateScene scene;
  final AzamanColors colors;
  final double size;

  /// 0 → 1 entrance progress. Animate this from the caller, or leave it at 1.
  final double progress;

  const AzStateIllustration({
    super.key,
    required this.scene,
    required this.colors,
    this.size = 96,
    this.progress = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AzStatePainter(
          scene: scene,
          colors: colors,
          progress: progress.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _AzStatePainter extends CustomPainter {
  final AzStateScene scene;
  final AzamanColors colors;
  final double progress;

  const _AzStatePainter({
    required this.scene,
    required this.colors,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Everything is drawn inside a 100x100 box and then scaled, so the painter
    // is resolution-independent and every scene shares one coordinate space.
    canvas.save();
    canvas.scale(size.width / 100.0, size.height / 100.0);
    switch (scene) {
      case AzStateScene.emptyBox:
        _drawBox(canvas);
        break;
      case AzStateScene.offline:
        _drawOffline(canvas);
        break;
      case AzStateScene.error:
        _drawError(canvas);
        break;
      case AzStateScene.search:
        _drawSearch(canvas);
        break;
      case AzStateScene.receipt:
        _drawReceipt(canvas);
        break;
    }
    canvas.restore();
  }

  Paint _stroke(double width, Color color, {bool soft = false}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color.withValues(alpha: soft ? 0.45 : 1.0);

  Paint _fill(Color color, double alpha) => Paint()
    ..style = PaintingStyle.fill
    ..color = color.withValues(alpha: alpha);

  /// Progressive reveal: draw only the first `progress` fraction of each path's
  /// length. All geometry here is polylines/arcs, so this is exact and cheap —
  /// and it means every scene "draws itself" with no extra code per scene.
  Path _progressive(Path path) {
    if (progress >= 1.0) return path;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
    }
    return out;
  }

  void _drawBox(Canvas canvas) {
    final lid = Path()
      ..moveTo(22, 42)
      ..lineTo(50, 30)
      ..lineTo(78, 42)
      ..lineTo(50, 54)
      ..close();
    final body = Path()
      ..moveTo(22, 42)
      ..lineTo(22, 72)
      ..lineTo(50, 84)
      ..lineTo(78, 72)
      ..lineTo(78, 42);
    final spine = Path()
      ..moveTo(50, 54)
      ..lineTo(50, 84);
    canvas.drawPath(_progressive(lid), _stroke(2.5, colors.accent));
    canvas.drawPath(_progressive(body), _stroke(2.5, colors.textTertiary));
    canvas.drawPath(
        _progressive(spine), _stroke(1.5, colors.textTertiary, soft: true));
  }

  void _drawOffline(Canvas canvas) {
    final cloud = Path()
      ..moveTo(30, 62)
      ..arcToPoint(const Offset(38, 46), radius: const Radius.circular(12))
      ..arcToPoint(const Offset(62, 44), radius: const Radius.circular(16))
      ..arcToPoint(const Offset(72, 62), radius: const Radius.circular(13))
      ..close();
    final slash = Path()
      ..moveTo(22, 78)
      ..lineTo(78, 26);
    canvas.drawPath(_progressive(cloud), _stroke(2.5, colors.textTertiary));
    canvas.drawPath(_progressive(slash), _stroke(3.0, colors.warning));
    canvas.drawCircle(const Offset(50, 84), 2.5, _fill(colors.warning, 0.8));
  }

  void _drawError(Canvas canvas) {
    final shield = Path()
      ..moveTo(50, 22)
      ..lineTo(74, 32)
      ..lineTo(74, 56)
      ..quadraticBezierTo(72, 76, 50, 84)
      ..quadraticBezierTo(28, 76, 26, 56)
      ..lineTo(26, 32)
      ..close();
    final bang = Path()
      ..moveTo(50, 40)
      ..lineTo(50, 60);
    canvas.drawPath(_progressive(shield), _stroke(2.5, colors.danger));
    canvas.drawPath(_progressive(bang), _stroke(3.0, colors.danger));
    canvas.drawCircle(const Offset(50, 69), 2.6, _fill(colors.danger, 1.0));
  }

  void _drawSearch(Canvas canvas) {
    final ring = Path()
      ..addOval(Rect.fromCircle(center: const Offset(44, 44), radius: 20));
    final handle = Path()
      ..moveTo(59, 59)
      ..lineTo(76, 76);
    canvas.drawPath(_progressive(ring), _stroke(2.5, colors.textTertiary));
    canvas.drawPath(_progressive(handle), _stroke(3.0, colors.accent));
    canvas.drawCircle(const Offset(44, 44), 3.0, _fill(colors.accent, 0.5));
  }

  void _drawReceipt(Canvas canvas) {
    final paper = Path()
      ..moveTo(32, 22)
      ..lineTo(68, 22)
      ..lineTo(68, 70)
      ..lineTo(62, 76)
      ..lineTo(56, 70)
      ..lineTo(50, 76)
      ..lineTo(44, 70)
      ..lineTo(38, 76)
      ..lineTo(32, 70)
      ..close();
    canvas.drawPath(_progressive(paper), _stroke(2.5, colors.textTertiary));
    for (var i = 0; i < 3; i++) {
      final y = 34.0 + i * 10;
      final line = Path()
        ..moveTo(40, y)
        ..lineTo(i == 2 ? 54 : 60, y);
      canvas.drawPath(
          _progressive(line), _stroke(1.5, colors.textTertiary, soft: true));
    }
  }

  @override
  bool shouldRepaint(covariant _AzStatePainter old) =>
      old.scene != scene ||
      old.progress != progress ||
      old.colors != colors;
}
