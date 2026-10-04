// =============================================================================
// UI-CORRECTION PHASE A — UI TYPOGRAPHY (2026-10-03)
//
// Comic Neue becomes the app's display/UI family (bundled locally in
// pubspec.yaml — never runtime-fetched), while money and numeric factories
// STAY on Inter for tabular-figure stability. Unavailable weights are
// mapped deliberately (Comic Neue ships 400 + 700 only):
//     800/900 → 700,   600/500 → 400,   400/700 stay.
//
// The money-pinning assertions fail against the pre-fix implementation
// (money()/delta() carried NO fontFamily), and the uiTheme wiring pins the
// deliberate weight mapping that the theme now uses.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_text.dart';

void main() {
  group('AzText — font family pins', () {
    test('money() stays on Inter — tabular figures, immune to UI font change',
        () {
      final style = AzText.money(Colors.black);
      expect(style.fontFamily, 'Inter');
      expect(style.fontFeatures, AzText.tabular);
      // An explicit size override keeps the pin.
      expect(AzText.money(Colors.black, size: 64).fontFamily, 'Inter');
    });

    test('delta() stays on Inter', () {
      expect(AzText.delta(Colors.black).fontFamily, 'Inter');
    });

    test('the numeric family constant is Inter, the UI family is ComicNeue',
        () {
      expect(AzText.numericFamily, 'Inter');
      expect(AzText.uiFamily, 'ComicNeue');
    });
  });

  group('AzText.mapUiWeight — deliberate weight mapping', () {
    test('800/900 map to 700, 600/500 map to 400, 400/700 ship as-is', () {
      expect(AzText.mapUiWeight(FontWeight.w800), FontWeight.w700);
      expect(AzText.mapUiWeight(FontWeight.w900), FontWeight.w700);
      expect(AzText.mapUiWeight(FontWeight.w600), FontWeight.w400);
      expect(AzText.mapUiWeight(FontWeight.w500), FontWeight.w400);
      expect(AzText.mapUiWeight(FontWeight.w700), FontWeight.w700);
      expect(AzText.mapUiWeight(FontWeight.w400), FontWeight.w400);
    });
  });

  group('AzText.uiTheme — the Comic-Neue UI text theme', () {
    test('every slot carries the Comic Neue family', () {
      final t = AzText.uiTheme();
      final slots = [
        t.displayLarge, t.displayMedium, t.displaySmall,
        t.headlineLarge, t.headlineMedium, t.headlineSmall,
        t.titleLarge, t.titleMedium, t.titleSmall,
        t.bodyLarge, t.bodyMedium, t.bodySmall,
        t.labelLarge, t.labelMedium, t.labelSmall,
      ];
      expect(slots.length, 15);
      for (final slot in slots) {
        expect(slot!.fontFamily, 'ComicNeue');
      }
    });

    test('unavailable weights are mapped: w800 → w700, w600/w500 → w400',
        () {
      final t = AzText.uiTheme();
      // hero (w800) and display (w800) render Bold.
      expect(t.displayLarge!.fontWeight, FontWeight.w700);
      expect(t.displayMedium!.fontWeight, FontWeight.w700);
      // title (w600) and bodyL (w500) render Regular.
      expect(t.titleLarge!.fontWeight, FontWeight.w400);
      expect(t.bodyLarge!.fontWeight, FontWeight.w400);
      // button (w700) keeps Bold.
      expect(t.labelLarge!.fontWeight, FontWeight.w700);
    });

    test('the Inter ladder (theme()) is untouched — money keeps its weights',
        () {
      final t = AzText.theme();
      expect(t.displayLarge!.fontWeight, FontWeight.w800);
      expect(t.titleLarge!.fontWeight, FontWeight.w600);
      expect(t.labelLarge!.fontWeight, FontWeight.w700);
      // The Inter-based ladder carries no pinned family — money factories
      // do that themselves.
      expect(t.displayLarge!.fontFamily, isNull);
    });
  });

  group('ThemeProvider — the app theme uses the Comic-Neue UI family', () {
    test('the app theme is Comic-Neue throughout; money text stays Inter',
        () {
      for (final theme in AzamanTheme.values) {
        final data = ThemeProvider.getThemeData(theme);
        // The theme's text theme carries the mapped Comic-Neue styles —
        // every slot, display and body alike (raw inline TextStyles inherit
        // this through DefaultTextStyle).
        expect(data.textTheme.displayLarge!.fontFamily, 'ComicNeue');
        expect(data.textTheme.bodyMedium!.fontFamily, 'ComicNeue');
        expect(
          data.textTheme.displayLarge!.fontWeight,
          FontWeight.w700, // hero was w800; mapped deliberately
        );
        // A money style remains Inter even inside the themed app.
        final money = AzText.money(data.textTheme.bodyLarge!.color!);
        expect(money.fontFamily, 'Inter');
      }
    });
  });
}
