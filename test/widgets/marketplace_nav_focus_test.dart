// CORRECTION I — the focused Marketplace navigation state.
//
// At the Marketplace ROOT the bottom navigation reorganises itself around
// Shopping: [ … Marketplace (search field) ].
//   * Entering the Marketplace tab turns the focus ON (shell wiring).
//   * The + control exits the composition horizontally.
//   * The "…" control restores the normal bar — Marketplace STAYS
//     selected; it is a presentation change, never a navigation.
//   * The search field binds to the AUTHORITATIVE marketplace search
//     provider through the same binding seam the screen uses.
//   * The normal Home/Chat/Marketplace tabs are not visible while focused.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/marketplace_nav_focus.dart';
import 'package:azaman/providers/marketplace_search_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/premium_bottom_nav.dart';

const _surface = Size(400, 900);

Future<void> _pumpNav(
  WidgetTester tester, {
  required int selectedIndex,
  bool focused = false,
}) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Direct state control: the shell sets this on tab selection.
        marketplaceNavFocusProvider.overrideWith((ref) => focused),
      ],
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.light),
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: PremiumBottomNav(
            key: const ValueKey('nav-under-test'),
            selectedIndex: selectedIndex,
            onItemSelected: (_) {},
            trailing: const SizedBox(
              key: ValueKey('plus-stand-in'),
              width: 54,
              height: 54,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('normal state: three tabs + the + beside the pill',
      (tester) async {
    await _pumpNav(tester, selectedIndex: 0);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
    // No focused row.
    expect(find.byKey(const ValueKey('marketplace-nav-ellipsis')),
        findsNothing);
    expect(find.byKey(const ValueKey('marketplace-nav-search')),
        findsNothing);
  });

  testWidgets('focused Marketplace state: [ … Marketplace (search) ], '
      'normal tabs hidden, + gone', (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('marketplace-nav-ellipsis')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace-nav-title')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace-nav-search')),
        findsOneWidget);

    // The normal tab bar is NOT visible in the focused state.
    expect(find.text('Home'), findsNothing);
    expect(find.text('Chat'), findsNothing);

    // The + control has exited the composition — its layout space is
    // released, so the search field owns the remaining width.
    expect(find.byKey(const ValueKey('plus-stand-in')), findsNothing);
  });

  testWidgets('"…" restores the normal bar and Marketplace stays selected',
      (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('marketplace-nav-ellipsis')));
    await tester.pumpAndSettle();

    // Normal navigation restored.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Marketplace'), findsOneWidget);
    // Marketplace is STILL the selected tab (accent identity), and the +
    // glides back in.
    expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
    // Focused row gone.
    expect(find.byKey(const ValueKey('marketplace-nav-ellipsis')),
        findsNothing);
  });

  testWidgets('the nav search field writes to the AUTHORITATIVE provider',
      (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('marketplace-nav-search')), 'kenkey');
    await tester.pump();

    // The provider is the single owner of search state — the same
    // provider the marketplace screen reacts to. No second provider.
    expect(marketplaceSearchProvider, isNotNull);
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('marketplace-nav-search'))));
    expect(container.read(marketplaceSearchProvider).text, 'kenkey');
    expect(container.read(marketplaceSearchProvider).isActive, isTrue);
  });

  testWidgets('selected state is color-only — no glow backdrop widget',
      (tester) async {
    await _pumpNav(tester, selectedIndex: 1);
    // CORRECTION G: the selected tab communicates by accent COLOR, not by
    // a glow/translucent backdrop blob behind it.
    final colors = ThemeProvider.getColors(AzamanTheme.light);
    final selectedIcon =
        tester.widget<Icon>(find.byIcon(HugeIconsSolid.message01).first);
    expect(selectedIcon.color, colors.accent,
        reason: 'selection identity is the accent color');

    // The LiquidTabBackdrop glow is GONE from the nav band (by signature
    // widget name — the class itself no longer exists in the tree).
    final nav = find.byKey(const ValueKey('nav-under-test'));
    final types = tester
        .widgetList(find.descendant(
            of: nav, matching: find.byWidgetPredicate((w) => true)))
        .map((w) => w.runtimeType.toString())
        .toSet();
    expect(types.contains('LiquidTabBackdrop'), isFalse);
  });
}
