// CORRECTION I — the focused Marketplace navigation state.
//
// At the Marketplace ROOT the bottom navigation reorganises itself around
// Shopping: [ back (marketplace icon) (search field) ] — UX-CORRECTION §3:
// icon + search only, the word "Marketplace" and the "…" glyph are gone.
//   * Entering the Marketplace tab turns the focus ON (shell wiring).
//   * The + control exits the composition horizontally.
//   * The back-arrow control restores the normal bar — Marketplace STAYS
//     selected; it is a presentation change, never a navigation.
//   * The search field binds to the AUTHORITATIVE marketplace search
//     provider through the same binding seam the screen uses.
//   * The normal Home/Chat/Marketplace tabs are not visible while focused.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
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
    // UX-CORRECTION §4 — icon-only resting nav: no text labels.
    expect(find.text('Home'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Marketplace'), findsNothing);
    // The three tab identities live on Semantics.
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Chat'), findsOneWidget);
    expect(find.bySemanticsLabel('Marketplace'), findsOneWidget);
    expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
    // No focused row.
    expect(find.byKey(const ValueKey('marketplace-nav-back')),
        findsNothing);
    expect(find.byKey(const ValueKey('marketplace-nav-search')),
        findsNothing);
  });

  testWidgets('focused Marketplace state: [ back icon (search) ], the word '
      'gone, normal tabs hidden, + gone', (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    // UX-CORRECTION §3 — back arrow replaces "…"; icon-only identity.
    expect(find.byKey(const ValueKey('marketplace-nav-back')),
        findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(HugeIconsSolid.store01), findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace-nav-search')),
        findsOneWidget);

    // The word "Marketplace" DISAPPEARS from the focused band.
    expect(find.byKey(const ValueKey('marketplace-nav-title')),
        findsNothing);
    expect(find.text('Marketplace'), findsNothing);

    // The normal tab bar is NOT visible in the focused state.
    expect(find.bySemanticsLabel('Home'), findsNothing);
    expect(find.bySemanticsLabel('Chat'), findsNothing);

    // The + control has exited the composition — its layout space is
    // released, so the search field owns the remaining width.
    expect(find.byKey(const ValueKey('plus-stand-in')), findsNothing);

    // The search field genuinely gets the extra width: it must be wider
    // than half the pill.
    expect(
        tester.getSize(
                find.byKey(const ValueKey('marketplace-nav-search')))
            .width,
        greaterThan(_surface.width / 2));
  });

  testWidgets('the back arrow restores the normal bar and Marketplace stays '
      'selected', (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('marketplace-nav-back')));
    await tester.pumpAndSettle();

    // Normal navigation restored (icon-only identities on Semantics).
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Chat'), findsOneWidget);
    expect(find.bySemanticsLabel('Marketplace'), findsOneWidget);
    // Marketplace is STILL the selected tab (accent identity), and the +
    // glides back in.
    expect(find.byKey(const ValueKey('plus-stand-in')), findsOneWidget);
    // Focused row gone.
    expect(find.byKey(const ValueKey('marketplace-nav-back')),
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


  // ── EXPERIENCE PASS §13 ──────────────────────────────────────────────────

  testWidgets('§13: normal → search is a MORPH inside the same pill, not a '
      'pop-swap', (tester) async {
    await _pumpNav(tester, selectedIndex: 2);

    // Flip the focused presentation on WITHOUT rebuilding the harness —
    // exactly the way the shell does. (The icon-only nav has no label
    // Text to hook any more — the band key is the stable hook.)
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('nav-under-test'))));
    container.read(marketplaceNavFocusProvider.notifier).state = true;

    // Mid-transition: BOTH presentations live inside the SAME pill
    // surface (the outgoing nav row is fading out while the focused row
    // fades in) — the band never unmounts.
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('nav-band-normal')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-band-focused')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-band-normal')), findsNothing);
    expect(find.byKey(const ValueKey('nav-band-focused')), findsOneWidget);
  });

  testWidgets('§13: the band sits directly above the IME — never behind it',
      (tester) async {
    await _pumpNav(tester, selectedIndex: 2, focused: true);
    await tester.pumpAndSettle();

    // Focus the in-band search field, then open a 300px keyboard.
    await tester.tap(find.byKey(const ValueKey('marketplace-nav-search')));
    await tester.pump();
    tester.view.viewInsets =
        FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await tester.pumpAndSettle();

    // The band's CONTENT (the padded pill surface, not the nav's outer
    // slot) must sit at or above the IME's top edge — never behind it.
    // The search field and the "…" control both live inside the pill.
    expect(
        tester.getRect(
            find.byKey(const ValueKey('marketplace-nav-search'))).bottom,
        lessThanOrEqualTo(_surface.height - 300));
    expect(
        tester.getRect(
            find.byKey(const ValueKey('marketplace-nav-back'))).bottom,
        lessThanOrEqualTo(_surface.height - 300));

    // The field is still hit-testable where it renders.
    expect(
        find
            .byKey(const ValueKey('marketplace-nav-search'))
            .hitTestable(),
        findsOneWidget);
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
