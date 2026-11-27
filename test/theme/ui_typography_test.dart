// =============================================================================
// UI TYPOGRAPHY
//
// Since 2026-11-27 (owner decision) words and numbers are both Inter, bundled
// locally in pubspec.yaml (never runtime-fetched); it replaced Comic Neue
// (Phase A, 2026-10-03). Inter is variable, so the UI ladder keeps its exact
// weights. Money and numeric factories pin the numeric family themselves.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';

void main() {
  group('AzText — font family pins', () {
    test(
      'money() stays on Inter — tabular figures, immune to UI font change',
      () {
        final style = AzText.money(Colors.black);
        expect(style.fontFamily, 'Inter');
        expect(style.fontFeatures, AzText.tabular);
        // An explicit size override keeps the pin.
        expect(AzText.money(Colors.black, size: 64).fontFamily, 'Inter');
      },
    );

    test('delta() stays on Inter', () {
      expect(AzText.delta(Colors.black).fontFamily, 'Inter');
    });

    test(
      'both families are Inter (owner decision 2026-11-27)',
      () {
        expect(AzText.numericFamily, 'Inter');
        expect(AzText.uiFamily, 'Inter');
      },
    );
  });

  group('AzText.mapUiWeight — Inter has every weight', () {
    test('every weight passes through unchanged', () {
      for (final w in FontWeight.values) {
        expect(AzText.mapUiWeight(w), w);
      }
    });
  });

  group('AzText.uiTheme — the Inter UI text theme', () {
    test('every slot carries the UI family', () {
      final t = AzText.uiTheme();
      final slots = [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ];
      expect(slots.length, 15);
      for (final slot in slots) {
        expect(slot!.fontFamily, 'Inter');
      }
    });

    test('the ladder keeps its exact weights (no folding)', () {
      final t = AzText.uiTheme();
      expect(t.displayLarge!.fontWeight, FontWeight.w800);
      expect(t.titleLarge!.fontWeight, FontWeight.w600);
      expect(t.bodyLarge!.fontWeight, FontWeight.w500);
      expect(t.labelLarge!.fontWeight, FontWeight.w700);
    });

    test(
      'the Inter ladder (theme()) is untouched — money keeps its weights',
      () {
        final t = AzText.theme();
        expect(t.displayLarge!.fontWeight, FontWeight.w800);
        expect(t.titleLarge!.fontWeight, FontWeight.w600);
        expect(t.labelLarge!.fontWeight, FontWeight.w700);
        // The Inter-based ladder carries no pinned family — money factories
        // do that themselves.
        expect(t.displayLarge!.fontFamily, isNull);
      },
    );
  });

  group('ThemeProvider — the app theme uses the UI family', () {
    test('the app theme is Inter throughout; money text stays Inter', () {
      for (final theme in AzamanTheme.values) {
        final data = ThemeProvider.getThemeData(theme);
        // The theme's text theme carries the UI-family styles —
        // every slot, display and body alike (raw inline TextStyles inherit
        // this through DefaultTextStyle).
        expect(data.textTheme.displayLarge!.fontFamily, 'Inter');
        expect(data.textTheme.bodyMedium!.fontFamily, 'Inter');
        expect(data.textTheme.displayLarge!.fontWeight, FontWeight.w800);
        // A money style remains Inter even inside the themed app.
        final money = AzText.money(data.textTheme.bodyLarge!.color!);
        expect(money.fontFamily, 'Inter');
      }
    });
  });
}
