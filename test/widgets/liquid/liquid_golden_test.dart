import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';

class _GooProbe extends CustomPainter {
  final double sigma;
  _GooProbe(this.sigma);

  @override
  void paint(Canvas canvas, Size size) {
    paintGoo(
      canvas,
      bounds: Offset.zero & size,
      sigma: sigma,
      body: const Color(0xFFFFFFFF),
      rim: const Color(0xFF1B1B1B),
      shapes: (c, p) {
        c.drawCircle(const Offset(70, 130), 26, p);
        drawNeck(c, p,
            from: const Offset(70, 130),
            to: const Offset(150, 70),
            baseRadius: 14,
            t: 1,
            tension: 0.7);
        c.drawPath(squirclePath(const Rect.fromLTWH(110, 30, 130, 80), 22), p);
      },
    );
  }

  @override
  bool shouldRepaint(_GooProbe old) => old.sigma != sigma;
}

void main() {
  // Run with: flutter test --update-goldens  (first time only)
  for (final sigma in [1.0, 4.0, 7.0]) {
    testWidgets('goo rim stays ~1px at sigma $sigma', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ColoredBox(
          color: const Color(0xFFE9E9E9),
          child: Center(
            child: RepaintBoundary(
              child: CustomPaint(size: const Size(280, 200), painter: _GooProbe(sigma)),
            ),
          ),
        ),
      ));
      await expectLater(
        find.byType(CustomPaint).last,
        matchesGoldenFile('goldens/goo_sigma_${sigma.toStringAsFixed(0)}.png'),
      );
    });
  }
}
