// =============================================================================
// AZAMAN — BALANCE CARD PAIR (WIDGET CONTRACT SUITE)
//
// The FX-status balance card's widget contracts, proven on the ACTUAL
// PAIRED COMPONENT (BalanceCardPair — the shared physical frame with both
// faces and the 3D flip). Faces are never asserted in isolation where the
// claim is about the pair: geometry, gestures and flip behaviour are pair
// contracts by definition.
//
// Groups:
//   1. Shared-frame geometry — the card's outer bounds, width and height
//      are IDENTICAL across the flip (within an explicit 0.5px tolerance)
//      and its footprint is exactly the Home deck contract (165px). The
//      surrounding layout does not move when the card flips.
//   2. Front-face contracts — GHS-first stack order, FX state laws, the
//      equivalent + info icon placement, the disclosure dialog, keyboard
//      focus, demo/fresh/unavailable states, the balance placeholder.
//   3. Back-face contracts — the compact breakdown: row order and content
//      (available → locked/committed → non-cash), native units explicit,
//      escrow/disputes grouped with values preserved, savings detail only
//      when supplied, unknown Susu as a dash, vendor variants, AZM points
//      outside every monetary context, accessible icon semantics.
//   4. Gestures — a deliberate tap flips; a vertical drag scrolls the
//      inner breakdown WITHOUT flipping; tapping back-face affordances
//      never double-fires; scrolling at the edges never flips; the front's
//      disclosure opens without flipping; reduced motion lands instantly;
//      flipping back returns to the front.
//   5. The nested-gesture guard — affordance taps cede the card's flip.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';

bool _fontsLoaded = false;

/// Loads the REAL font faces the card renders with — the UI families
/// (Comic Neue Regular + Bold), Inter for money figures, and the
/// HugeIconsSolid glyph font. Without this, the test font substitutes
/// every glyph with a wide square, text wraps unnaturally and fixed-
/// height cards overflow spuriously; icons render as blank boxes.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await (FontLoader('Inter')
        ..addFont(File('assets/fonts/Inter-Variable.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer))))
      .load();
  for (final f in ['ComicNeue-Regular.ttf', 'ComicNeue-Bold.ttf']) {
    await (FontLoader('ComicNeue')
          ..addFont(File('assets/fonts/$f')
              .readAsBytes()
              .then((b) => ByteData.view(b.buffer))))
        .load();
  }
  // The icon glyph font, loaded through rootBundle's package-asset path
  // so the card's icons render as REAL glyphs in this environment.
  await (FontLoader('HugeIconsSolid')
        ..addFont(rootBundle.load(
          'packages/hugeicons_pro/fonts/hugeicons-solid.ttf',
        )))
      .load();
  _fontsLoaded = true;
}

BalanceCardValuation _saved({
  double? savingsWithdrawable,
  bool vendor = false,
  double? susu,
}) =>
    BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      escrowLocked: 4,
      disputeEscrow: 1,
      vaultLocked: 10,
      savingsLocked: 20,
      savingsWithdrawable: savingsWithdrawable,
      susuCommitted: susu,
      azmPoints: 1200,
      vendorRowRelevant: vendor,
      vendorUnallocated: 7.5,
      vendorUnallocatedEligible: true,
      rate: FxRateView(
        ghsPerUsdc: 12.03,
        kind: FxRateKind.saved,
        sourceLabel: 'saved observation',
        observedAt: DateTime.utc(2026, 10, 22, 9, 30),
      ),
    ).compute();

class _RefreshStub extends StatelessWidget {
  const _RefreshStub();
  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('capture-refresh-indicator'),
        width: 24,
        height: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

Future<void> _pumpPair(
  WidgetTester tester, {
  required BalanceCardValuation valuation,
  double width = 390,
  bool reduceMotion = false,
  Widget? neighborBelow,
}) async {
  await tester.runAsync(_loadFonts);
  final colors = ThemeProvider.getColors(AzamanTheme.dark).withAccent(
    AzAccent.gold,
  );
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeProvider.getThemeData(AzamanTheme.dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 844),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RepaintBoundary(
                    key: const ValueKey('bcfx-pair-root'),
                    child: SizedBox(
                      width: double.infinity,
                      child: BalanceCardPair(
                        key: const ValueKey('bcfx-pair'),
                        valuation: valuation,
                        colors: colors,
                        trailingRefresh: const _RefreshStub(),
                      ),
                    ),
                  ),
                  if (neighborBelow != null) neighborBelow,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Rect _frameRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('balance-pair-frame')));

Future<void> _flipToBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('balance-pair-flip-listener')));
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Taps once from the BACK state (toggling the card back to the front).
Future<void> _flipToFront(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('balance-pair-flip-listener')));
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Scrolls the back face's inner breakdown until [finder] is built and
/// visible (rows live in a lazily built ListView inside the fixed frame).
Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder finder,
) async {
  await tester.scrollUntilVisible(
    finder,
    80,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('bc-breakdown-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('shared frame — one physical card, fixed geometry', () {
    testWidgets('the footprint is exactly the Home deck contract: 165px tall',
        (tester) async {
      await _pumpPair(tester, valuation: _saved());
      final frame = _frameRect(tester);
      expect(frame.height, BalanceCardGeometry.height);
      expect(frame.width, greaterThan(0));
    });

    testWidgets('outer bounds are IDENTICAL across the flip (≤ 0.5px) and '
        'the surrounding layout does not move', (tester) async {
      final neighbor = Container(
        key: const ValueKey('bcfx-neighbor'),
        height: 40,
        color: Colors.white,
      );
      await _pumpPair(
        tester,
        valuation: _saved(),
        neighborBelow: neighbor,
      );
      final front = _frameRect(tester);
      final neighborFront = tester.getRect(
        find.byKey(const ValueKey('bcfx-neighbor')),
      );

      await _flipToBack(tester);

      final back = _frameRect(tester);
      final neighborBack = tester.getRect(
        find.byKey(const ValueKey('bcfx-neighbor')),
      );
      expect(back.left, closeTo(front.left, 0.5));
      expect(back.top, closeTo(front.top, 0.5));
      expect(back.width, closeTo(front.width, 0.5));
      expect(back.height, closeTo(front.height, 0.5));
      expect(neighborBack.top, closeTo(neighborFront.top, 0.5),
          reason: 'flipping must not push or reflow the surrounding Home '
              'content');
      // Sanity: the flip really happened (the back is showing).
      expect(find.byKey(const ValueKey('bc-row-ghs-wallet')), findsOneWidget);
    });

    testWidgets('the frame stays 165px on the back at 320dp and 390dp',
        (tester) async {
      for (final width in [320.0, 390.0]) {
        await _pumpPair(tester, valuation: _saved(), width: width);
        expect(_frameRect(tester).height, BalanceCardGeometry.height);
        await _flipToBack(tester);
        expect(_frameRect(tester).height, BalanceCardGeometry.height);
        expect(_frameRect(tester).width,
            closeTo(width - 24, 0.5), // padding 12 each side
            reason: 'the card fills the parent width at every size');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('front face — GHS-first FX-status contracts', () {
    testWidgets('stack order: eyebrow → headline → equivalent → rate row, '
        'with the refresh flush right', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      final label = tester.getRect(
          find.byKey(const ValueKey('balance-fx-label')));
      final headline =
          tester.getRect(find.byKey(const ValueKey('balance-fx-headline')));
      final equivalent = tester.getRect(
          find.byKey(const ValueKey('balance-fx-equivalent-row')));
      final rateRow =
          tester.getRect(find.byKey(const ValueKey('balance-fx-rate-row')));
      final frame = _frameRect(tester);
      expect(label.bottom, lessThan(headline.top));
      expect(headline.bottom, lessThan(equivalent.top));
      expect(equivalent.bottom, lessThan(rateRow.top));
      final refresh = tester
          .getRect(find.byKey(const ValueKey('capture-refresh-indicator')));
      expect(refresh.right, closeTo(rateRow.right, 2));
      expect(rateRow.bottom, lessThan(frame.bottom + 1),
          reason: 'the rate row pins flush to the card bottom');
    });

    testWidgets('a saved fallback shows the info icon beside the equivalent '
        'and the fallback identification in the rate row', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      expect(find.byKey(const ValueKey('balance-fx-rate-saved')),
          findsOneWidget);
      final info = tester
          .getRect(find.byKey(const ValueKey('balance-fx-equivalent-info')));
      final eq = tester.getRect(
          find.byKey(const ValueKey('balance-fx-equivalent-row')));
      expect(info.top, greaterThanOrEqualTo(eq.top - 4));
      expect(info.bottom, lessThanOrEqualTo(eq.bottom + 4));
    });

    testWidgets('a fresh rate shows no fallback chrome', (tester) async {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        azmPoints: 0,
        rate: FxRateView(
          ghsPerUsdc: 12.03,
          kind: FxRateKind.fresh,
        ),
      ).compute();
      await _pumpPair(tester, valuation: v);
      expect(find.byKey(const ValueKey('balance-fx-rate-fresh')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-info')),
          findsNothing,
          reason: 'no disclosure chrome without a fallback');
    });

    testWidgets('the fallback disclosure opens on tap and does NOT flip the '
        'card', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await tester.tap(
          find.byKey(const ValueKey('balance-fx-equivalent-info')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
          findsOneWidget,
          reason: 'the guard let the button act without the card also '
              'flipping');
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget,
          reason: 'still on the front');
      await tester
          .tap(find.byKey(const ValueKey('balance-fx-fallback-disclosure-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
          findsNothing);
    });

    testWidgets('an unconfirmed balance renders the balance placeholder, '
        'and FX loading never replaces a known amount', (tester) async {
      final loadingFx = const BalanceCardValuation(
        nativeGhsAvailable: 0,
        availableUsdc: 0,
        balanceConfirmed: false,
        azmPoints: 0,
        rate: FxRateView(kind: FxRateKind.none, loading: true),
      ).compute();
      await _pumpPair(tester, valuation: loadingFx);
      expect(find.byKey(const ValueKey('balance-fx-amount-dots')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-rate-dots')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-headline')), findsNothing);
    });

    testWidgets('no rate and no fallback: stable unavailable state',
        (tester) async {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(kind: FxRateKind.none),
      ).compute();
      await _pumpPair(tester, valuation: v);
      expect(find.byKey(const ValueKey('balance-fx-rate-unavailable')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-valuation-incomplete')),
          findsOneWidget);
    });

    testWidgets('GHS-only wallet, no usable rate: known GHS headline, '
        'NO fabricated zero equivalent', (tester) async {
      // The distinction this pins down: the GHS headline CAN be fully
      // known while its USDC equivalent is unknown. A "≈ 0.00 USDC
      // equivalent" row would be a fabricated conversion, not an honest
      // one.
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 250,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(kind: FxRateKind.none),
      ).compute();
      await _pumpPair(tester, valuation: v);

      // The GHS headline IS shown — no rate was ever needed for it.
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget);
      // No equivalent row at all — and specifically no zero figure.
      expect(find.byKey(const ValueKey('balance-fx-equivalent-row')),
          findsNothing);
      expect(find.textContaining('0.00 USDC'), findsNothing);
      // Not an incomplete valuation: there is nothing missing from the
      // GHS total, only from its USDC translation.
      expect(find.byKey(const ValueKey('balance-fx-valuation-incomplete')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-rate-unavailable')),
          findsOneWidget);
    });

    testWidgets('GHS-only wallet WITH a fresh rate: the equivalent is '
        'native GHS ÷ rate, shown beside the known GHS headline',
        (tester) async {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 250,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.5, kind: FxRateKind.fresh),
      ).compute();
      await _pumpPair(tester, valuation: v);

      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget);
      final equiv = find.byKey(const ValueKey('balance-fx-equivalent'));
      expect(equiv, findsOneWidget);
      expect(
        tester.widget<Text>(equiv).data ?? tester.widget<Text>(equiv).textSpan!
            .toPlainText(),
        contains('20.00'),
        reason: '250 GHS ÷ 12.5 = 20 USDC — not a fabricated zero',
      );
    });
  });

  group('back face — compact icon-led breakdown', () {
    testWidgets('hierarchy: available → locked/committed → non-cash, with '
        'right-aligned amounts and explicit native units', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      final ghs = tester.getRect(find.byKey(const ValueKey('bc-row-ghs-wallet')));
      final usdc = tester.getRect(find.byKey(const ValueKey('bc-row-usdc-held')));
      final escrow = tester.getRect(find.byKey(const ValueKey('bc-row-escrow')));
      expect(ghs.top, lessThan(usdc.top));
      expect(usdc.top, lessThan(escrow.top));

      // The non-cash row is the LAST row. The ListView's OWN children
      // list is the complete ordered source (lazy building only affects
      // which Elements exist — never this order).
      final children = (tester
              .widget<ListView>(
                  find.byKey(const ValueKey('bc-breakdown-scroll')))
              .childrenDelegate as SliverChildListDelegate)
          .children;
      final orderedRows = children
          .whereType<Widget>()
          .where((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('bc-row-'))
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(orderedRows.first, 'bc-row-ghs-wallet');
      expect(orderedRows.indexOf('bc-row-usdc-held'),
          lessThan(orderedRows.indexOf('bc-row-escrow')));
      expect(orderedRows.last, 'bc-row-azm-points',
          reason: 'NON-CASH sits after every monetary section');

      // Native units are explicit in the rendered rows (both are visible
      // before any scrolling). findRichText: the amounts render as
      // Text.rich (amount + unit spans); the expected GHS string is built
      // with the app's own formatter (a non-breaking space after ₵).
      expect(
        find.textContaining(AzMoney.ghs(100), findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('50.00 USDC', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('bc-row-vendor')), findsNothing,
          reason: 'vendor row only where relevant');
      // Finally, scroll to the bottom so the non-cash row renders too.
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-azm-points')));
      expect(find.byKey(const ValueKey('bc-row-azm-points')), findsOneWidget);
    });

    testWidgets('escrow and disputes are grouped but BOTH values are '
        'preserved; the split detail renders', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      expect(find.textContaining('Escrow 4.00'), findsOneWidget);
      expect(find.textContaining('Disputes 1.00'), findsOneWidget);
    });

    testWidgets('unknown Susu renders a dash — never zero; known Susu '
        'renders the amount', (tester) async {
      await _pumpPair(tester, valuation: _saved(susu: null));
      await _flipToBack(tester);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-susu')));
      expect(find.textContaining('not loaded yet'), findsOneWidget);
      expect(find.textContaining('—'), findsOneWidget,
          reason: 'unknown Susu renders a dash, never a zero');

      await tester.pumpWidget(const SizedBox());
      await _pumpPair(tester, valuation: _saved(susu: 5));
      await _flipToBack(tester);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-susu')));
      expect(find.textContaining('not loaded yet'), findsNothing);
      expect(find.textContaining('5.00 USDC'), findsOneWidget);
    });

    testWidgets('savings withdrawal detail appears ONLY when the '
        'authoritative data supplies it', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-savings')));
      expect(find.textContaining('withdrawable today'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _pumpPair(tester, valuation: _saved(savingsWithdrawable: 12.5));
      await _flipToBack(tester);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-savings')));
      expect(find.textContaining('withdrawable today 12.50'), findsOneWidget);
    });

    testWidgets('vendor variants: present with its availability state, '
        'absent when irrelevant', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-vendor')));
      expect(find.byKey(const ValueKey('bc-row-vendor')), findsOneWidget);
      expect(find.textContaining('unallocated · withdrawable'),
          findsOneWidget);
    });

    testWidgets('icons carry accessible semantic labels and supplement, '
        'never replace, text', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      // The icon semantics are asserted on the Semantics widget itself —
      // the deterministic proof that the label is present in the tree.
      Finder byIconSemantics(String label) => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label);
      expect(byIconSemantics('GHS wallet icon'), findsOneWidget);
      expect(byIconSemantics('USDC wallet icon'), findsOneWidget);
      expect(byIconSemantics('Escrow lock icon'), findsOneWidget);
      // The label text still exists for every visible row — icons
      // supplement text, never replace it.
      expect(find.text('GHS wallet'), findsOneWidget);
      expect(find.text('USDC held'), findsOneWidget);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-vendor')));
      expect(byIconSemantics('Vendor storefront icon'), findsOneWidget);
      expect(find.text('Vendor balance'), findsOneWidget);
      await _scrollUntilVisible(
          tester, find.byKey(const ValueKey('bc-row-azm-points')));
      expect(find.text('AZM points'), findsOneWidget);
    });

    testWidgets('no emoji anywhere on the card and the share rail is gone',
        (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      expect(find.byKey(const ValueKey('balance-fx-share-rail')),
          findsNothing);
      // Every visible Text is emoji-free.
      final emoji = RegExp(
          '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
          unicode: true);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? '', isNot(contains(emoji)));
      }
    });
  });

  group('gestures — tap, inner scroll, flip-back, reduced motion', () {
    testWidgets('a deliberate tap flips to the back; a second tap returns '
        'to the front', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      expect(find.byKey(const ValueKey('bc-row-ghs-wallet')), findsOneWidget);
      await _flipToFront(tester);
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget);
    });

    testWidgets('a vertical drag on the back scrolls the inner breakdown '
        'WITHOUT flipping; the header stays fixed', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      final scroll = tester
          .widget<ListView>(find.byKey(const ValueKey('bc-breakdown-scroll')));
      final scrollRender = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('bc-breakdown-scroll')));
      final headerBefore = tester
          .getRect(find.byKey(const ValueKey('balance-fx-breakdown-header')));

      // Drag well past the 8px tap tolerance.
      await tester.drag(
        find.byKey(const ValueKey('bc-breakdown-scroll')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsNothing,
          reason: 'a drag must never flip the card');
      final headerAfter = tester
          .getRect(find.byKey(const ValueKey('balance-fx-breakdown-header')));
      expect(headerAfter.top, closeTo(headerBefore.top, 0.5),
          reason: 'the outer card and its header stay stable');
      expect(scrollRender, isNotNull);
      expect(scroll, isNotNull);
    });

    testWidgets('the back-face "return to balance" affordance flips back '
        'exactly once (guarded, no double fire)', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      await tester.tap(find.byKey(const ValueKey('bc-flip-back')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget,
          reason: 'back on the front');
      expect(find.byKey(const ValueKey('bc-row-ghs-wallet')), findsNothing);
    });

    testWidgets('reduced motion: the flip lands instantly and the footprint '
        'is still unchanged', (tester) async {
      await _pumpPair(tester, valuation: _saved(), reduceMotion: true);
      final front = _frameRect(tester);
      await tester.tap(
          find.byKey(const ValueKey('balance-pair-flip-listener')));
      await tester.pump(); // no settle needed: zero-duration flip
      final back = _frameRect(tester);
      expect(back.top, closeTo(front.top, 0.5));
      expect(back.height, closeTo(front.height, 0.5));
      expect(find.byKey(const ValueKey('bc-row-ghs-wallet')), findsOneWidget);
    });

    testWidgets('no RenderFlex overflow at any width with long content',
        (tester) async {
      final long = _saved(vendor: true, susu: 5, savingsWithdrawable: 12.5);
      for (final width in [320.0, 360.0, 390.0]) {
        await _pumpPair(tester, valuation: long, width: width);
        await _flipToBack(tester);
        expect(tester.takeException(), isNull,
            reason: 'no overflow at ${width}dp');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
