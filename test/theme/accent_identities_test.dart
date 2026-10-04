// =============================================================================
// TASK-025 — Accent identities regression guards.
//
// Pins the four-identity accent system end to end:
//   • the identity table itself (exactly four families, exact hex values);
//   • the additive withAccent() contract (surfaces/semantics untouched);
//   • ThemeProvider persistence (azaman_accent, gold fallback);
//   • the historical static baseline (getThemeData(theme) / getColors(theme)
//     keep their pre-TASK-025 visuals so existing callers never regress);
//   • the session-only vertical override (apply, clear, never persist);
//   • the settings picker (four discs, provider updates on tap);
//   • WCAG contrast for all eight light/dark × accent combinations.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_vertical_accent.dart';
import 'package:azaman/widgets/sensory_preferences_section.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('identity table', () {
    test('1. AzAccent exposes exactly four identities', () {
      expect(AzAccent.values, hasLength(4));
      expect(AzAccent.values, containsAll(<AzAccent>[
        AzAccent.gold,
        AzAccent.teal,
        AzAccent.indigo,
        AzAccent.rose,
      ]));
    });

    test('2. gold on light reproduces the existing light accent values', () {
      final historical = ThemeProvider.getColors(AzamanTheme.light);
      final gold = historical.withAccent(AzAccent.gold);
      // The exact accent, secondary and glow the light theme shipped with.
      expect(gold.accent, historical.accent);
      expect(gold.accentSecondary, historical.accentSecondary);
      expect(gold.glow, historical.glow);
      // Explicit family table values, not just "whatever getColors has".
      expect(gold.accent, const Color(0xFFB8860B));
      expect(gold.accentSecondary, const Color(0xFF8B6914));
    });

    test('3. gold in dark is gold, not the historical dark teal', () {
      final darkGold =
          ThemeProvider.getColors(AzamanTheme.dark).withAccent(AzAccent.gold);
      expect(darkGold.accent, const Color(0xFFE0AE3A));
      expect(darkGold.accent, isNot(const Color(0xFF2DD4BF)));
      // The historical dark teal remains reachable — as the Teal identity.
      final darkTeal =
          ThemeProvider.getColors(AzamanTheme.dark).withAccent(AzAccent.teal);
      expect(darkTeal.accent, ThemeProvider.getColors(AzamanTheme.dark).accent);
      expect(darkTeal.accent, const Color(0xFF2DD4BF));
    });

    test('4. every accent changes accent/secondary/glow per family', () {
      for (final isDark in <bool>[false, true]) {
        final base = isDark
            ? ThemeProvider.getColors(AzamanTheme.dark)
            : ThemeProvider.getColors(AzamanTheme.light);
        for (final a in AzAccent.values) {
          final family = AzAccentFamily.all[a]!;
          final c = base.withAccent(a);
          expect(c.accent, family.accentFor(isDark), reason: '$a accent');
          expect(
            c.accentSecondary,
            family.secondaryFor(isDark),
            reason: '$a secondary',
          );
          expect(c.glow, family.accentFor(isDark), reason: '$a glow');
          expect(c.onAccent, family.onAccentFor(isDark), reason: '$a onAccent');
        }
      }
    });

    test('5. withAccent leaves the surface ladder and semantics untouched', () {
      for (final theme in AzamanTheme.values) {
        final base = ThemeProvider.getColors(theme);
        for (final a in AzAccent.values) {
          final c = base.withAccent(a);
          expect(c.isDark, base.isDark);
          expect(c.background, base.background);
          expect(c.surface, base.surface);
          expect(c.card, base.card);
          expect(c.softSurface, base.softSurface);
          expect(c.divider, base.divider);
          expect(c.success, base.success);
          expect(c.danger, base.danger);
          expect(c.warning, base.warning);
          expect(c.textPrimary, base.textPrimary);
          expect(c.textSecondary, base.textSecondary);
          expect(c.textTertiary, base.textTertiary);
          expect(c.scaffoldBackground, base.scaffoldBackground);
          expect(c.border, base.border);
        }
      }
    });
  });

  group('ThemeProvider.getThemeData', () {
    test('6. the historical no-accent call still works and matches the baseline', () {
      for (final theme in AzamanTheme.values) {
        final historical = ThemeProvider.getColors(theme);
        final data = ThemeProvider.getThemeData(theme);
        // Pre-TASK-025 callers keep their exact visuals: the static baseline
        // is the historical identity (gold on light, teal on dark).
        expect(data.colorScheme.primary, historical.accent, reason: '$theme');
        expect(data.primaryColor, historical.accent);
        expect(data.brightness, ThemeProvider.brightnessOf(historical));
      }
    });

    test('7. an explicit accent maps colorScheme.primary to the family accent', () {
      for (final theme in AzamanTheme.values) {
        final isDark = theme == AzamanTheme.dark;
        for (final a in AzAccent.values) {
          final data = ThemeProvider.getThemeData(theme, accent: a);
          expect(
            data.colorScheme.primary,
            AzAccentFamily.all[a]!.accentFor(isDark),
            reason: '$theme $a',
          );
          expect(
            data.colorScheme.primary,
            ThemeProvider.getColors(theme).withAccent(a).accent,
          );
        }
      }
    });

    test('8. M3 roles stay populated and non-lavender in all combinations', () {
      for (final theme in AzamanTheme.values) {
        final isDark = theme == AzamanTheme.dark;
        for (final a in AzAccent.values) {
          final c = ThemeProvider.getColors(theme).withAccent(a);
          final scheme =
              ThemeProvider.getThemeData(theme, accent: a).colorScheme;
          expect(scheme.onSurfaceVariant, c.textSecondary);
          expect(scheme.surfaceContainerHighest, c.card);
          expect(scheme.primaryContainer, c.accentSurface);
          expect(scheme.outlineVariant, c.divider);
          // Material's baseline lavender must never leak through.
          expect(scheme.primary, isNot(const Color(0xFF6750A4)));
          expect(scheme.primary, isNot(const Color(0xFFD0BCFF)));
          expect(scheme.onSurfaceVariant, isNot(const Color(0xFF49454F)));
          // Sanity: the accent really is this family's, not the seed fallback.
          expect(scheme.primary, AzAccentFamily.all[a]!.accentFor(isDark));
        }
      }
    });
  });

  group('accent persistence', () {
    Future<ThemeProvider> loaded({Map<String, Object> values = const {}}) async {
      SharedPreferences.setMockInitialValues(values);
      final p = ThemeProvider();
      // The constructor's prefs read is async; wait for it to land.
      int guard = 0;
      while (!p.isLoaded && guard++ < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(p.isLoaded, isTrue);
      return p;
    }

    test('9a. missing stored value falls back to gold', () async {
      final p = await loaded();
      expect(p.accent, AzAccent.gold);
    });

    test('9b. invalid stored value falls back to gold', () async {
      final p = await loaded(values: <String, Object>{'azaman_accent': 99});
      expect(p.accent, AzAccent.gold);
    });

    test('9c. selecting teal persists teal; reload returns teal', () async {
      final p = await loaded();
      await p.setAccent(AzAccent.teal);
      expect(p.accent, AzAccent.teal);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_accent'), AzAccent.teal.index);
      // Force-quit/relaunch simulation: a fresh provider over the same prefs.
      final reopened = await loaded(values: <String, Object>{
        'azaman_accent': prefs.getInt('azaman_accent') as Object,
      });
      expect(reopened.accent, AzAccent.teal);
    });
  });

  group('contrast (WCAG 1.4.11 UI-component bar of 3.0)', () {
    test('10. every light/dark × accent pair meets accent/onAccent contrast', () {
      // WCAG relative luminance.
      double luminance(Color color) {
        // Color.r/.g/.b are linear 0..1 doubles — no /255 normalization.
        double channel(double s) =>
            s <= 0.03928 ? s / 12.92 : _pow(s);

        return 0.2126 * channel(color.r) +
            0.7152 * channel(color.g) +
            0.0722 * channel(color.b);
      }

      double contrast(Color a, Color b) {
        final la = luminance(a);
        final lb = luminance(b);
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final theme in AzamanTheme.values) {
        final base = ThemeProvider.getColors(theme);
        for (final a in AzAccent.values) {
          final c = base.withAccent(a);
          final ratio = contrast(c.accent, c.onAccent);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '$theme × $a accent/onAccent contrast ${ratio.toStringAsFixed(2)}',
          );
        }
      }
    });
  });

  group('shell resolution', () {
    test('16. shell resolution uses vertical when set, user accent otherwise', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // No vertical: the user's saved accent (default gold) drives the shell.
      expect(
        container.read(resolvedAzamanColorsProvider).accent,
        AzAccentFamily.all[AzAccent.gold]!.lightAccent,
      );
      // A vertical is active: its session accent wins.
      container.read(verticalAccentProvider.notifier).state = AzAccent.teal;
      expect(
        container.read(resolvedAzamanColorsProvider).accent,
        AzAccentFamily.all[AzAccent.teal]!.lightAccent,
      );
      // Cleared: back to the user's accent.
      container.read(verticalAccentProvider.notifier).state = null;
      expect(
        container.read(resolvedAzamanColorsProvider).accent,
        AzAccentFamily.all[AzAccent.gold]!.lightAccent,
      );
    });
  });

  group('settings picker', () {
    Widget harness(ThemeProvider tp) => ProviderScope(
          overrides: [themeProvider.overrideWith((ref) => tp)],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: SensoryPreferencesSection())),
          ),
        );

    Finder discs() => find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('accent_disc_'),
        );

    testWidgets('11. AccentIdentityRow renders exactly four discs', (tester) async {
      final p = (await tester.runAsync(_loadedProvider))!;
      await tester.pumpWidget(harness(p));
      expect(discs(), findsNWidgets(4));
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Your accent, everywhere in Azaman'), findsOneWidget);
    });

    testWidgets('12. selecting a disc updates the provider', (tester) async {
      final p = (await tester.runAsync(_loadedProvider))!;
      await tester.pumpWidget(harness(p));
      expect(p.accent, AzAccent.gold);
      await tester.tap(discs().at(1)); // teal
      await tester.pump();
      expect(p.accent, AzAccent.teal);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_accent'), AzAccent.teal.index);
    });
  });

  group('vertical accent scope', () {
    testWidgets('13. the scope applies a session-only override', (tester) async {
      final p = (await tester.runAsync(_loadedProvider))!;
      final container = ProviderContainer(
        overrides: [themeProvider.overrideWith((ref) => p)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AzVerticalAccentScope(
              accent: AzAccent.rose,
              child: SizedBox(),
            ),
          ),
        ),
      );
      // The post-frame apply has run by the end of the first pump.
      expect(container.read(verticalAccentProvider), AzAccent.rose);
      // The shell resolves through the vertical accent while it is active.
      expect(
        container.read(resolvedAzamanColorsProvider).accent,
        _shellAccent(AzAccent.rose, p),
      );
      // Unmount the scope while the container is still alive, so the
      // addTearDown(container.dispose) never races the scope's deactivate.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
    });

    testWidgets('14. leaving/disposal clears the vertical override', (tester) async {
      final p = (await tester.runAsync(_loadedProvider))!;
      final container = ProviderContainer(
        overrides: [themeProvider.overrideWith((ref) => p)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AzVerticalAccentScope(
              accent: AzAccent.rose,
              child: SizedBox(),
            ),
          ),
        ),
      );
      expect(container.read(verticalAccentProvider), AzAccent.rose);
      // Pop the scope: the override clears and the saved identity returns.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      expect(container.read(verticalAccentProvider), isNull);
      // EXPERIENCE PASS §3: the saved identity resolves through the
      // current theme's brightness, whatever that theme is. The resolver
      // honours the user's ACCENT FAMILY (gold), not the theme's own
      // identity accent — hence _shellAccent(p.accent, p).
      expect(
        container.read(resolvedAzamanColorsProvider).accent,
        _shellAccent(p.accent, p),
      );
    });

    testWidgets('15. a vertical override never changes the persisted user accent', (tester) async {
      final p = (await tester.runAsync(_loadedProvider))!;
      await p.setAccent(AzAccent.indigo);
      final container = ProviderContainer(
        overrides: [themeProvider.overrideWith((ref) => p)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AzVerticalAccentScope(
              accent: AzAccent.rose,
              child: SizedBox(),
            ),
          ),
        ),
      );
      expect(container.read(verticalAccentProvider), AzAccent.rose);
      // The provider-level identity and the persisted value are untouched.
      expect(p.accent, AzAccent.indigo);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_accent'), AzAccent.indigo.index);
      // ...and after leaving the vertical, the user's indigo returns.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      expect(container.read(resolvedAzamanColorsProvider).accent,
          _shellAccent(AzAccent.indigo, p));
    });

  });
}

/// A fully loaded ThemeProvider over fresh (empty) mock prefs, with all async
/// constructor work settled — shared by the widget tests so each starts clean.
///
/// Inside testWidgets the binding runs in a fake-async zone where plain
/// `Future.delayed` timers never fire on their own, so there the loop advances
/// the fake clock with `tester.pump` instead.
/// EXPERIENCE PASS §3: the accent resolves through the CURRENT theme's
/// brightness. The loaded provider has no saved preference, so the default
/// is now dark — assertions must follow the theme instead of assuming light.
Color _shellAccent(AzAccent accent, ThemeProvider p) =>
    p.currentTheme == AzamanTheme.dark
        ? AzAccentFamily.all[accent]!.darkAccent
        : AzAccentFamily.all[accent]!.lightAccent;

Future<ThemeProvider> _loadedProvider() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final p = ThemeProvider();
  int guard = 0;
  while (!p.isLoaded && guard++ < 100) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(p.isLoaded, isTrue);
  return p;
}

/// Linearized sRGB channel for WCAG relative luminance.
double _pow(double s) => math.pow((s + 0.055) / 1.055, 2.4).toDouble();
