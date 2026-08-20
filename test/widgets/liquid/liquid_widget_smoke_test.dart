import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';
import 'package:azaman/widgets/liquid/liquid_placement.dart';
import 'package:azaman/widgets/liquid/liquid_dropdown_menu.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';
import 'package:azaman/providers/theme_provider.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.light);

void main() {
  // These tests verify the widget logic without triggering the goo CustomPaint,
  // which uses ui.ImageFilter.compose + ui.ColorFilter.matrix — known to
  // segfault flutter_tester in headless mode. The full rendering is verified
  // via the APK build and unit tests for engine + placement.

  testWidgets('LiquidDropdownMenu trigger renders with correct semantics', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: LiquidDropdownMenu(
            colors: _colors,
            items: [
              LiquidDropdownItem(icon: Icons.camera, label: 'Camera', onTap: () {}),
              LiquidDropdownItem(icon: Icons.image, label: 'Gallery', onTap: () {}),
            ],
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.bySemanticsLabel('Attachments'), findsOneWidget);
  });

  test('LiquidPhase state machine guards', () {
    expect(LiquidPhase.values.length, 4);
    expect(LiquidPhase.values, contains(LiquidPhase.closed));
    expect(LiquidPhase.values, contains(LiquidPhase.opening));
    expect(LiquidPhase.values, contains(LiquidPhase.open));
    expect(LiquidPhase.values, contains(LiquidPhase.closing));
  });

  test('kLiquidMinTapTarget is 44dp', () {
    expect(kLiquidMinTapTarget, 44.0);
  });

  group('solvePanel integration', () {
    test('panel fits on 320dp screen from bottom-left anchor', () {
      final safe = LiquidSafeArea(
        screen: const Size(320, 640),
        padding: const EdgeInsets.only(top: 24, bottom: 16),
      );
      final anchor = const Rect.fromLTWH(14, 560, 44, 44);
      final p = solvePanel(
        anchor: anchor,
        panel: const Size(200, 240),
        safe: safe,
      );
      expect(p.rect.left, greaterThanOrEqualTo(safe.left - 0.01));
      expect(p.rect.right, lessThanOrEqualTo(safe.right + 0.01));
      expect(p.above, isTrue);
    });
  });

  group('solveArc integration', () {
    test('all pills on screen at 320dp', () {
      final safe = LiquidSafeArea(
        screen: const Size(320, 640),
        padding: const EdgeInsets.only(top: 24, bottom: 16),
      );
      final anchor = const Rect.fromLTWH(32, 300, 120, 44);
      final sizes = List.generate(6, (i) => Size(110 + i * 14, 44));
      final slots = solveArc(anchor: anchor, sizes: sizes, safe: safe);
      expect(slots.length, 6);
      for (final s in slots) {
        expect(s.rect.left, greaterThanOrEqualTo(safe.left - 0.01));
        expect(s.rect.right, lessThanOrEqualTo(safe.right + 0.01));
      }
    });
  });
}
