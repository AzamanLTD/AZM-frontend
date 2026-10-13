// =============================================================================
// THEMES SCREEN TESTS  (Home/Settings refresh §8, 2026-10-13)
//
// The Themes page is now the single destination for the identity/colour
// experience. Pinned here:
//   • the appearance cards (Light / Dark) with the live selected state;
//   • the active summary reflecting theme + accent immediately;
//   • the full eight-swatch palette committing instantly and persisting;
//   • the accent-in-context preview tracking the active identity.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/theme_picker_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ThemeProvider> loadedProvider() async {
    final p = ThemeProvider();
    int guard = 0;
    while (!p.isLoaded && guard++ < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(p.isLoaded, isTrue);
    return p;
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
  }

  Widget harness(ThemeProvider tp) => UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [themeProvider.overrideWith((ref) => tp)],
    ),
    child: const MaterialApp(home: ThemePickerScreen()),
  );

  group('appearance', () {
    testWidgets('renders both appearance cards with Dark active by default', (
      tester,
    ) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      expect(p.currentTheme, AzamanTheme.dark);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      // The default stays dark (EXPERIENCE PASS §3) — the screen must not
      // accidentally flip it just by being opened.
      expect(p.accent, AzAccent.gold);
    });

    testWidgets('tapping Light switches the theme and persists it', (
      tester,
    ) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      await tapVisible(tester, find.text('Light'));
      await tester.pumpAndSettle();
      expect(p.currentTheme, AzamanTheme.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_theme'), AzamanTheme.light.index);
    });
  });

  group('active summary', () {
    testWidgets('shows the live theme and accent immediately', (tester) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        find.byKey(const ValueKey('themes_active_summary')),
        findsOneWidget,
      );
      expect(find.text('Dark · Gold'), findsOneWidget);

      // Commit a different accent: the summary follows with no restart.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('accent_swatch_indigo')),
      );
      await tester.pumpAndSettle();
      // SliverList unmounts offscreen children — bring the summary back
      // into view so the assertion reads the live widget.
      await tester.drag(find.byType(Scrollable), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(find.text('Dark · Indigo'), findsOneWidget);
    });
  });

  group('accent palette', () {
    testWidgets('a swatch commit applies instantly and persists', (
      tester,
    ) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      await tapVisible(
        tester,
        find.byKey(const ValueKey('accent_swatch_violet')),
      );
      await tester.pumpAndSettle();
      expect(p.accent, AzAccent.violet);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_accent'), AzAccent.violet.index);
    });

    testWidgets('the context preview tracks the active identity', (
      tester,
    ) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      // The context preview sits below the fold — scroll it into view so
      // the SliverList actually builds it before we assert on it.
      await tester.drag(find.byType(Scrollable), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('themes_context_preview')),
        findsOneWidget,
      );
      expect(find.textContaining('Gold'), findsWidgets);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('accent_swatch_emerald')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Emerald'), findsWidgets);
    });
  });

  group('persistence round-trip', () {
    testWidgets('a reopened provider restores the saved accent and theme', (
      tester,
    ) async {
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      // Light is visible at the top; commit it first so we never have to
      // scroll back up past the palette (SliverList unmounts offscreen items).
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('accent_swatch_coral')),
      );
      await tester.pumpAndSettle();

      // Fresh provider over the same prefs — the "restart" simulation.
      // Must run inside runAsync: real Future.delayed waits hang fake async.
      final q = (await tester.runAsync(() async {
        final fresh = ThemeProvider();
        int guard = 0;
        while (!fresh.isLoaded && guard++ < 100) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        return fresh;
      }))!;
      expect(q.isLoaded, isTrue);
      expect(q.accent, AzAccent.coral);
      expect(q.currentTheme, AzamanTheme.light);
    });
  });
}
