// =============================================================================
// AZAMAN — Custom Send Button with Logo Fill Animation
//
// Replaces the standard send icon with the three-part Azaman logo, rotated
// 45° to match the orientation of a traditional send arrow. When pressed:
//   1. Parts fill with black sequentially: biggest -> middle -> smallest
//   2. When all 3 are filled, the message is sent
//   3. Parts unfill in reverse: smallest -> middle -> biggest
//
// The fill animation uses opacity transitions per part — each part "lights
// up" with black in sequence, creating a swift but clearly visible cascade.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class AzamanSendButton extends StatefulWidget {
  final Color accentColor;
  final Color outlineColor;
  final Color fillColor;
  final VoidCallback onSend;
  final bool isDark;

  const AzamanSendButton({
    super.key,
    required this.accentColor,
    required this.outlineColor,
    required this.fillColor,
    required this.onSend,
    required this.isDark,
  });

  @override
  State<AzamanSendButton> createState() => _AzamanSendButtonState();
}

class _AzamanSendButtonState extends State<AzamanSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    reverseDuration: const Duration(milliseconds: 360),
  );

  bool _isAnimating = false;

  // Same SVG paths as az_logo_refresh_indicator.dart
  static const String _viewBox = "20 20 569 553";

  static const String _part1 =
      "M408.0,167.5 L398.0,166.5 L364.0,150.5 L331.0,139.5 L307.0,136.5 L274.0,140.5 L270.0,143.5 L237.0,153.5 L207.0,167.5 L195.0,164.5 L188.5,152.0 L199.5,130.0 L212.5,115.0 L215.5,108.0 L270.5,45.0 L273.5,39.0 L277.5,37.0 L277.5,34.0 L295.0,20.5 L313.0,19.5 L314.0,21.5 L315.0,19.5 L332.5,36.0 L341.5,49.0 L346.5,52.0 L349.5,58.0 L379.5,91.0 L412.5,136.0 L418.5,148.0 L419.5,156.0 L414.5,164.0 L408.0,167.5 Z";
  static const String _part2 =
      "M461.0,327.5 L450.0,325.5 L423.0,312.5 L371.0,294.5 L336.0,287.5 L326.0,288.5 L311.0,285.5 L283.0,286.5 L283.0,288.5 L271.0,287.5 L257.0,290.5 L256.0,292.5 L250.0,291.5 L240.0,295.5 L237.0,294.5 L219.0,302.5 L216.0,301.5 L185.0,312.5 L159.0,325.5 L147.0,327.5 L136.0,324.5 L127.5,315.0 L125.5,296.0 L143.5,272.0 L151.5,266.0 L161.0,253.5 L195.0,223.5 L219.0,206.5 L237.0,197.5 L239.0,194.5 L274.0,180.5 L294.0,177.5 L296.0,175.5 L312.0,175.5 L340.0,182.5 L361.0,192.5 L363.0,191.5 L371.0,197.5 L373.0,196.5 L378.0,201.5 L392.0,207.5 L400.0,215.5 L406.0,217.5 L448.5,254.0 L454.5,263.0 L471.5,278.0 L469.5,279.0 L479.5,290.0 L483.5,301.0 L482.5,310.0 L478.5,318.0 L474.0,322.5 L461.0,327.5 Z";
  static const String _part3 =
      "M563.0,572.5 L551.0,570.5 L539.0,562.5 L537.0,563.5 L531.0,557.5 L485.0,530.5 L414.0,497.5 L408.0,497.5 L402.0,493.5 L363.0,483.5 L359.0,484.5 L358.0,482.5 L348.0,480.5 L317.0,477.5 L267.0,479.5 L251.0,482.5 L250.0,484.5 L236.0,485.5 L195.0,497.5 L165.0,509.5 L123.0,530.5 L69.0,562.5 L58.0,571.5 L56.0,569.5 L46.0,572.5 L34.0,568.5 L21.5,555.0 L19.5,543.0 L21.5,543.0 L24.5,529.0 L38.5,496.0 L37.5,494.0 L42.5,487.0 L41.5,484.0 L53.5,459.0 L54.5,451.0 L71.0,431.5 L108.0,402.5 L110.0,403.5 L123.0,393.5 L160.0,372.5 L185.0,360.5 L190.0,360.5 L196.0,355.5 L198.0,356.5 L214.0,349.5 L239.0,344.5 L240.0,342.5 L282.0,337.5 L283.0,335.5 L325.0,335.5 L327.0,337.5 L345.0,338.5 L381.0,346.5 L397.0,352.5 L401.0,351.5 L400.0,353.5 L403.0,352.5 L417.0,360.5 L423.0,360.5 L444.0,371.5 L449.0,371.5 L456.0,378.5 L466.0,381.5 L477.0,389.5 L479.0,388.5 L488.0,396.5 L503.0,404.5 L542.0,435.5 L554.5,453.0 L557.5,463.0 L559.5,463.0 L562.5,477.0 L582.5,522.0 L584.5,533.0 L588.5,538.0 L587.5,553.0 L582.5,561.0 L577.0,566.5 L563.0,572.5 Z";

  late final Path _path1;
  late final Path _path2;
  late final Path _path3;

  @override
  void initState() {
    super.initState();
    _path1 = _parsePath(_part1);
    _path2 = _parsePath(_part2);
    _path3 = _parsePath(_part3);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_isAnimating) return;
    setState(() => _isAnimating = true);
    _c.forward(from: 0).whenComplete(() {
      // All 3 parts filled — send the message
      widget.onSend();
      // Reverse: unfill from smallest -> middle -> biggest
      _c.reverse().whenComplete(() {
        if (mounted) setState(() => _isAnimating = false);
      });
    });
  }

  /// Per-part fill opacity derived from the controller value (0->1).
  /// Part 1 (biggest): fills during t=[0.0, 0.33]
  /// Part 2 (middle):  fills during t=[0.33, 0.66]
  /// Part 3 (smallest): fills during t=[0.66, 1.0]
  /// When controller reverses (1->0), parts naturally unfill in reverse order.
  double _fillForPart(int part, double t) {
    const seg = 1.0 / 3;
    final start = part * seg;
    return ((t - start) / seg).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isAnimating ? null : _handleTap,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: widget.accentColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = _c.value;
              return Transform.rotate(
                angle: math.pi / 4, // 45 deg — same orientation as a send arrow
                child: CustomPaint(
                  size: const Size(22, 22),
                  painter: _AzamanSendPainter(
                    path1: _path1,
                    path2: _path2,
                    path3: _path3,
                    viewBox: _viewBox,
                    fill1: _fillForPart(0, t),
                    fill2: _fillForPart(1, t),
                    fill3: _fillForPart(2, t),
                    outlineColor: widget.outlineColor,
                    fillColor: widget.fillColor,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Painter — draws 3-part Azaman logo with progressive black fill
// =============================================================================

class _AzamanSendPainter extends CustomPainter {
  final Path path1;
  final Path path2;
  final Path path3;
  final String viewBox;
  final double fill1;
  final double fill2;
  final double fill3;
  final Color outlineColor;
  final Color fillColor;

  _AzamanSendPainter({
    required this.path1,
    required this.path2,
    required this.path3,
    required this.viewBox,
    required this.fill1,
    required this.fill2,
    required this.fill3,
    required this.outlineColor,
    required this.fillColor,
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

    // Outline all 3 parts as a subtle guide
    final outlinePaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (final p in [path1, path2, path3]) {
      canvas.drawPath(p, outlinePaint);
    }

    // Fill parts progressively with black
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
  bool shouldRepaint(_AzamanSendPainter old) =>
      old.fill1 != fill1 ||
      old.fill2 != fill2 ||
      old.fill3 != fill3 ||
      old.outlineColor != outlineColor ||
      old.fillColor != fillColor;
}

// =============================================================================
// SVG Path Parser (same as az_logo_refresh_indicator.dart)
// =============================================================================

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
