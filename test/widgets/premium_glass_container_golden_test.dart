// Golden-image harness for the premium surfaces.
//
// Locks the rendered pixels of PremiumGlassContainer in both brightnesses so
// any change to the v2 directional lighting (specular streak, rim, thickness
// hairline, two-layer shadow) shows up as an intentional, reviewable diff
// rather than as a silent visual regression on device.
//
// Regenerate with:  flutter test --update-goldens test/widgets/premium_glass_container_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/premium_glass_container.dart';

import '../goldens/golden_harness.dart';

/// Surface geometry, pixel ratio and reduced-motion override all come from
/// [pumpGoldenSurface] — see `test/goldens/golden_harness.dart`.
Future<void> _pumpSurface(
  WidgetTester tester, {
  required Brightness brightness,
  required bool directionalLight,
}) {
  return pumpGoldenSurface(
    tester,
    brightness: brightness,
    home: goldenNoMotion(
      Scaffold(
        body: Center(
          child: RepaintBoundary(
            child: SizedBox(
              width: 280,
              child: PremiumGlassContainer(
                directionalLight: directionalLight,
                padding: const EdgeInsets.all(20),
                child: const Text('Azaman', textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('PremiumGlassContainer v2 — $name', (tester) async {
      await _pumpSurface(
        tester,
        brightness: brightness,
        directionalLight: true,
      );
      await expectLater(
        find.byType(PremiumGlassContainer),
        matchesGoldenFile('goldens/premium_glass_container_$name.png'),
      );
    });

    testWidgets('PremiumGlassContainer v1 fallback — $name', (tester) async {
      await _pumpSurface(
        tester,
        brightness: brightness,
        directionalLight: false,
      );
      await expectLater(
        find.byType(PremiumGlassContainer),
        matchesGoldenFile('goldens/premium_glass_container_v1_$name.png'),
      );
    });
  }
}
