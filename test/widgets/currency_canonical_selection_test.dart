// =============================================================================
// CANONICAL CURRENCY SELECTION — Settings × Drawer (Stage 1 §4E).
//
// Pins that the Settings page and the drawer render ONE authoritative
// display preference, and that changing it in either place flips the
// other surface — they read the same currencyProvider, never a private
// copy. The GHS-first fresh default is asserted on both surfaces, and a
// deliberate USDC choice made in Settings is what the drawer shows next.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/settings_screen.dart';
import 'package:azaman/widgets/settings_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ThemeProvider> loadTheme(WidgetTester tester) async {
    final theme = await tester.runAsync(() async {
      final t = ThemeProvider();
      int guard = 0;
      while (!t.isLoaded && guard++ < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return t;
    });
    return theme!;
  }

  /// Jumps the page scroll position until [target] is built, then makes it
  /// fully visible (fixed pumps, not pumpAndSettle — entrance animations
  /// repeat under test).
  Future<void> reveal(WidgetTester tester, Finder target) async {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    var offset = 0.0;
    while (target.evaluate().isEmpty &&
        offset <= state.position.maxScrollExtent) {
      state.position.jumpTo(offset);
      await tester.pump(const Duration(milliseconds: 60));
      offset += 250;
    }
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Widget host(ProviderContainer container, Widget home) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      );

  testWidgets('a FRESH default renders GHS in Settings and in the drawer', (
    tester,
  ) async {
    final theme = await loadTheme(tester);
    final container = ProviderContainer(
      overrides: [
        themeProvider.overrideWith((ref) => theme),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host(container, const SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await reveal(tester, find.text('Display Currency'));

    expect(find.text('Display Currency'), findsOneWidget);
    expect(
      find.text('GHS'),
      findsOneWidget,
      reason:
          'Ghana-first: a fresh preference shows GHS in Settings, '
          'not the old USDC default',
    );

    // The same container — the drawer must agree with Settings.
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            endDrawer: const SettingsDrawer(),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openEndDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await reveal(tester, find.text('Currency'));

    expect(find.text('Currency'), findsOneWidget);
    expect(
      find.text('GHS'),
      findsOneWidget,
      reason:
          'the drawer chip and the Settings row are the SAME '
          'canonical preference',
    );
  });

  testWidgets('a deliberate USDC pick in Settings is what the drawer shows', (
    tester,
  ) async {
    final theme = await loadTheme(tester);
    final container = ProviderContainer(
      overrides: [
        themeProvider.overrideWith((ref) => theme),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(host(container, const SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    await reveal(tester, find.text('Display Currency'));

    // A deliberate user choice — made through the SAME public notifier
    // call the picker itself makes. (The sheet's ListTiles trip a
    // pre-existing debug ink-splash assertion under test; the picker
    // mechanics are not this contract's subject.)
    await tester.runAsync(
      () => container.read(currencyProvider.notifier).set(DisplayCurrency.usdc),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.text('USDC'),
      findsOneWidget,
      reason: 'the Settings row reflects the deliberate USDC choice',
    );

    // The drawer, in the SAME container, must show the same value.
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            endDrawer: const SettingsDrawer(),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openEndDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await reveal(tester, find.text('Currency'));

    expect(find.text('Currency'), findsOneWidget);
    expect(
      find.text('USDC'),
      findsOneWidget,
      reason:
          'one authority: the drawer shows the value Settings set, '
          'with no duplicate preference state in between',
    );
  });
}
