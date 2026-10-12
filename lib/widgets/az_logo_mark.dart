// =============================================================================
// AZ LOGO MARK — the real AZM brand mark as a reusable 3-part painted logo
//
// Extracted from the chat send button's logo treatment (azaman_send_button.dart)
// so other surfaces can reuse the SAME geometry and painter vocabulary instead
// of re-inventing a similar-looking symbol.
//
// The logo consists of three path segments (top peak, middle band, base).
// This widget renders the outline plus an optional per-part fill, where the
// caller decides the fill ORDER and progress semantics:
//
//   * The chat send button fills TOP→DOWN sequentially (each segment empties
//     the previous one on reverse) — it keeps its own private painter.
//   * The Home action launcher fills BOTTOM-UP CUMULATIVELY (a lower segment
//     stays filled while the next one fills) — see plus_action_launcher.dart.
//
// Rendering contract: viewBox "20 20 569 553", parsed with the same strict
// SVG path parser used by azaman_send_button.dart.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

class AzLogoMark extends StatelessWidget {
  /// Per-part fill opacities in LOGICAL SEGMENT order: index 0 = part1 (top
  /// peak), 1 = part2 (middle band), 2 = part3 (base). 0 = outline only.
  final double fill1;
  final double fill2;
  final double fill3;

  final Color outlineColor;
  final Color fillColor;

  /// Upright brand mark. The chat send button renders rotated 45°; pass
  /// [rotationQuarterTurns] only if a caller genuinely needs that treatment.
  final int rotationQuarterTurns;

  final Size size;

  const AzLogoMark({
    super.key,
    required this.outlineColor,
    required this.fillColor,
    required this.size,
    this.fill1 = 0,
    this.fill2 = 0,
    this.fill3 = 0,
    this.rotationQuarterTurns = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotationQuarterTurns * math.pi / 2,
      child: CustomPaint(
        size: size,
        painter: _AzLogoPainter(
          outlineColor: outlineColor,
          fillColor: fillColor,
          fill1: fill1,
          fill2: fill2,
          fill3: fill3,
        ),
      ),
    );
  }
}

class _AzLogoPainter extends CustomPainter {
  final double fill1;
  final double fill2;
  final double fill3;
  final Color outlineColor;
  final Color fillColor;

  _AzLogoPainter({
    required this.fill1,
    required this.fill2,
    required this.fill3,
    required this.outlineColor,
    required this.fillColor,
  });

  // Same SVG paths as azaman_send_button.dart / az_logo_refresh_indicator.dart.
  static const String _viewBox = "20 20 569 553";

  static const String _part1 =
      "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z";
  static const String _part2 =
      "M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z";
  static const String _part3 =
      "M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z";

  static final Path path1 = _parsePath(_part1);
  static final Path path2 = _parsePath(_part2);
  static final Path path3 = _parsePath(_part3);

  @override
  void paint(Canvas canvas, Size size) {
    final parts = _viewBox.split(' ');
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

    final outlinePaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final p in [path1, path2, path3]) {
      canvas.drawPath(p, outlinePaint);
    }

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (fill1 > 0) {
      fillPaint.color = fillColor.withValues(alpha: fill1);
      canvas.drawPath(path1, fillPaint);
    }
    if (fill2 > 0) {
      fillPaint.color = fillColor.withValues(alpha: fill2);
      canvas.drawPath(path2, fillPaint);
    }
    if (fill3 > 0) {
      fillPaint.color = fillColor.withValues(alpha: fill3);
      canvas.drawPath(path3, fillPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AzLogoPainter old) =>
      old.fill1 != fill1 ||
      old.fill2 != fill2 ||
      old.fill3 != fill3 ||
      old.outlineColor != outlineColor ||
      old.fillColor != fillColor;
}

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
