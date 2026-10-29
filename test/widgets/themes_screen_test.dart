// =============================================================================
// THEMES SCREEN TESTS — card-identity edition.
//
// The page used to host an eight-swatch INDEPENDENT accent picker. That
// control is retired (P2): the applied balance card owns the app accent, and
// it can only be changed by applying a card. What this file now pins:
//   • the appearance cards (Light / Dark) with the live selected state;
//   • the active summary reflecting theme + card immediately;
//   • the card-identity block naming the applied card, with NO swatches left
//     anywhere in the tree;
//   • a card change reaching the page without the page being rebuilt by hand;
//   • a reopened provider restoring the saved theme AND card.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/theme_picker_screen.dart';
import 'package:azaman/theme/balance_card_brand.dart';

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

  /// A TALL viewport: the page is a lazy ListView, so a phone-sized window
  /// never builds the lower sections (the context preview). Giving the test a
  /// tall surface builds the whole page instead of scrolling by guesswork.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      expect(p.currentTheme, AzamanTheme.dark);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsWidgets);
      // The default stays dark (EXPERIENCE PASS §3) — merely opening the
      // page must never flip it.
      expect(p.currentTheme, AzamanTheme.dark);
    });

    testWidgets('tapping Light switches the theme and persists it', (
      tester,
    ) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      await tapVisible(tester, find.text('Light').first);
      await tester.pumpAndSettle();
      expect(p.currentTheme, AzamanTheme.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('azaman_theme'), AzamanTheme.light.index);
    });
  });

  group('card identity', () {
    testWidgets('the identity block names the applied card', (tester) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        find.byKey(const ValueKey('themes_card_identity')),
        findsOneWidget,
      );
      final label = tester.widget<Text>(
        find.byKey(const ValueKey('themes_card_identity_label')),
      );
      expect(label.data, contains('Blue card'));
    });

    testWidgets('NO independent accent swatch survives', (tester) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      for (final name in [
        'gold',
        'teal',
        'indigo',
        'rose',
        'blue',
        'violet',
        'emerald',
        'coral',
      ]) {
        expect(
          find.byKey(ValueKey('accent_swatch_$name')),
          findsNothing,
          reason: 'the retired $name swatch must not be reachable',
        );
      }
    });

    testWidgets('a card change reaches the page live', (tester) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      await tester.runAsync(() => p.setCardVariant(BalanceCardVariant.green));
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(
        find.byKey(const ValueKey('themes_card_identity_label')),
      );
      expect(label.data, contains('Green card'));
    });

    testWidgets('the active summary still tracks the theme', (tester) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        find.byKey(const ValueKey('themes_active_summary')),
        findsOneWidget,
      );
      expect(find.textContaining('Dark · Blue card'), findsOneWidget);

      await tapVisible(tester, find.text('Light').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Light · Blue card'), findsOneWidget);
    });

    testWidgets('the context preview is still rendered', (tester) async {
      tallView(tester);
      final p = (await tester.runAsync(loadedProvider))!;
      await tester.pumpWidget(harness(p));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.byKey(const ValueKey('themes_context_preview')),
        findsOneWidget,
      );
    });
  });

  group('persistence', () {
    testWidgets('a reopened provider restores theme and card', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'azaman_theme': AzamanTheme.light.index,
        kBalanceCardVariantPrefKey: 'azadark',
      });
      final q = (await tester.runAsync(loadedProvider))!;
      expect(q.isLoaded, isTrue);
      expect(q.currentTheme, AzamanTheme.light);
      expect(q.cardVariant, BalanceCardVariant.dark);

      await tester.pumpWidget(harness(q));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('Light · Dark card'), findsOneWidget);
    });
  });
}
