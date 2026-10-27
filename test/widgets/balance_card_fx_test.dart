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
//      and its footprint is exactly the Home deck contract (180px). The
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
import 'package:azaman/utils/az_money.dart';
import 'package:azaman/providers/theme_provider.dart';
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
  bool vendor = false,
  double? susu,
  double? native = 100,
  double? vault = 10,
  double? savings = 20,
}) =>
    BalanceCardValuation(
      nativeGhsAvailable: native,
      availableUsdc: 50,
      balanceConfirmed: true,
      escrowLocked: 4,
      disputeEscrow: 1,
      vaultLocked: vault,
      savingsLockedGhs: savings,
      susuCommitted: susu,
      azmPoints: 1200,
      vendorRowRelevant: vendor,
      vendorUnallocatedUsdc: 7.5,
      rate: FxRateView(
        ghsPerUsdc: 12.03,
        kind: FxRateKind.saved,
        sourceLabel: 'saved observation',
        observedAt: DateTime.utc(2026, 10, 22, 9, 30),
      ),
    ).compute();

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
  // Tap the EYEBROW band, not the card's center: at narrow capture
  // widths the center falls on the disclosure info button, whose
  // nested-gesture guard correctly suppresses the flip. The eyebrow is
  // a neutral region — the only control in it is the flip itself.
  await tester.tap(find.byKey(const ValueKey('balance-fx-label')));
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
/// Drags the back face's SECTION PAGER exactly ONE section down and
/// settles. The distance is computed from the pager's real geometry
/// (viewportFraction 0.86): a fraction of one page, far enough to snap
/// forward, never far enough to skip a section.
Future<void> _pageDown(WidgetTester tester) async {
  final pager = find.byKey(const ValueKey('bc-section-pager'));
  final pagerHeight = tester.getRect(pager).height;
  await tester.drag(pager, Offset(0, -(pagerHeight * 0.86 * 0.75)));
  await tester.pumpAndSettle();
}


void main() {
  group('shared frame — one physical card, fixed geometry', () {
    testWidgets('the footprint is exactly the Home deck contract: 180px tall',
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

    testWidgets('the frame stays 180px on the back at 320dp and 390dp',
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


  group('PR-C: data-independent geometry + truthful FX refresh states', () {
    // ───────────────────────────────────────────────────────────────────
    // The 2026-10-27 UX pass: the restored 180px footprint reserves ONE
    // fixed region per section (GHS headline / USDC line / FX status) and
    // NO data state may move them; the FX row reports a genuine refresh
    // truthfully — the valid rate STAYS on screen with an inline updating
    // indication, instead of vanishing behind the initial-fetch dots.
    // ───────────────────────────────────────────────────────────────────

    BalanceCardValuation freshVal({bool loading = false}) =>
        BalanceCardValuation(
          nativeGhsAvailable: 100,
          availableUsdc: 50,
          balanceConfirmed: true,
          rate: FxRateView(
            ghsPerUsdc: 12.03,
            kind: FxRateKind.fresh,
            loading: loading,
          ),
        ).compute();

    testWidgets('the three reserved regions NEVER move across every '
        'data state — and the footprint is 180px in all of them',
        (tester) async {
      final states = <String, BalanceCardValuation>{
        'fresh rate': freshVal(),
        'genuine refresh (rate retained + loading)': freshVal(loading: true),
        'saved fallback': _saved(),
        'unavailable rate': const BalanceCardValuation(
          nativeGhsAvailable: 100,
          availableUsdc: 50,
          balanceConfirmed: true,
          rate: FxRateView(kind: FxRateKind.none),
        ).compute(),
        'USDC held, no GHS valuation (no rate, no native wallet)':
            const BalanceCardValuation(
          availableUsdc: 50,
          balanceConfirmed: true,
          rate: FxRateView(kind: FxRateKind.none),
        ).compute(),
        'balance loading': const BalanceCardValuation(
          balanceConfirmed: false,
          rate: FxRateView(kind: FxRateKind.none, loading: true),
        ).compute(),
      };

      Rect? headline;
      Rect? secondary;
      Rect? rateRow;
      double? frameHeight;
      for (final entry in states.entries) {
        await _pumpPair(tester, valuation: entry.value);
        final h = tester
            .getRect(find.byKey(const ValueKey('balance-fx-headline-slot')));
        final sec = tester.getRect(
            find.byKey(const ValueKey('balance-fx-secondary-slot')));
        final rr = tester
            .getRect(find.byKey(const ValueKey('balance-fx-rate-row')));
        final fh = _frameRect(tester).height;
        expect(fh, BalanceCardGeometry.height,
            reason: '${entry.key}: the footprint is the fixed 180px deck '
                'contract in EVERY state');
        if (headline != null) {
          expect(h.top, closeTo(headline.top, 0.5),
              reason: '${entry.key}: the GHS headline region must be '
                  'identical whether its value is present, loading or '
                  'unavailable');
          expect(sec.top, closeTo(secondary!.top, 0.5),
              reason: '${entry.key}: the USDC line region never moves');
          expect(rr.bottom, closeTo(rateRow!.bottom, 0.5),
              reason: '${entry.key}: the FX status region stays pinned flush '
                  'to the card bottom');
        }
        headline = h;
        secondary = sec;
        rateRow = rr;
        frameHeight = fh;
      }
      expect(frameHeight, BalanceCardGeometry.height);
    });

    testWidgets('a genuine refresh KEEPS the valid rate on screen and adds '
        'the inline updating indication — never the initial-fetch dots',
        (tester) async {
      await _pumpPair(tester, valuation: freshVal(loading: true));

      // The rate stays visible, in its own node, unchanged.
      expect(find.byKey(const ValueKey('balance-fx-rate-fresh')),
          findsOneWidget);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('balance-fx-rate-fresh')))
            .data,
        startsWith('1 USDC ≈ GH'),
        reason: 'the valid rate value is not removed during a refresh');
      // The refresh indication appears beside it.
      expect(find.byKey(const ValueKey('balance-fx-rate-refreshing')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-rate-refresh-dots')),
          findsOneWidget);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('balance-fx-rate-refresh-label')))
            .data,
        'Updating…',
      );
      // The initial-fetch presentation (dots REPLACING the rate) must NOT
      // be used when a rate is already on screen.
      expect(find.byKey(const ValueKey('balance-fx-rate-dots')),
          findsNothing);
      expect(find.text('Updating rate…'), findsNothing);
      expect(_frameRect(tester).height, BalanceCardGeometry.height);
    });

    testWidgets('an initial fetch (NO rate yet) still shows the animated '
        'dots + updating caption — and never the refresh row',
        (tester) async {
      await _pumpPair(
        tester,
        valuation: const BalanceCardValuation(
          nativeGhsAvailable: 100,
          availableUsdc: 50,
          balanceConfirmed: true,
          rate: FxRateView(kind: FxRateKind.none, loading: true),
        ).compute(),
      );
      expect(find.byKey(const ValueKey('balance-fx-rate-dots')),
          findsOneWidget);
      expect(find.text('Updating rate…'), findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-rate-refreshing')),
          findsNothing);
    });

    testWidgets('an idle fresh rate shows NO indicator at all — the dots '
        'are never decorative', (tester) async {
      await _pumpPair(tester, valuation: freshVal());
      expect(find.byKey(const ValueKey('balance-fx-rate-fresh')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-rate-refreshing')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-rate-dots')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-rate-updating')),
          findsNothing);
    });
  });

  group('front face — GHS-first FX-status contracts', () {
    testWidgets('stack order: eyebrow → headline → equivalent → rate row, '
        'in one left-side cluster', (tester) async {
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

    testWidgets('a fresh rate with a NATIVE GHS wallet shows no fallback '
        'chrome but keeps the breakdown disclosure', (tester) async {
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
          findsOneWidget,
          reason: 'the disclosure stays available even without a '
              'fallback — it explains the equivalent');
      expect(find.textContaining('Using saved rate'), findsNothing,
          reason: 'no fallback chrome in the rate row');

      // The headline is the NATIVE GHS balance only — USDC held never
      // enters it (owner-corrected contract 2026-10-27): 100 native GHS,
      // NOT 100 + 50 × 12.03 = 701.50.
      final semantics = tester.firstWidget<Semantics>(
        find.descendant(
          of: find.byKey(const ValueKey('balance-fx-headline')),
          matching: find.byType(Semantics),
        ),
      );
      expect(semantics.properties.label,
          'Available balance ${AzMoney.ghs(100)} in GHS');
      // The equivalent is derived FROM that GHS balance: 100 / 12.03.
      expect(find.byKey(const ValueKey('balance-fx-equivalent')),
          findsOneWidget);

      // The disclosure says the USDC line is the equivalent converted
      // FROM the GHS balance — never GHS derived from USDC.
      await tester.tap(
          find.byKey(const ValueKey('balance-fx-equivalent-info')));
      await tester.pumpAndSettle();
      final body = find.byKey(
          const ValueKey('balance-fx-fallback-disclosure-body'));
      expect(body, findsOneWidget);
      // The body key sits on the Text itself — read its data directly.
      final bodyText = tester.widget<Text>(body).data;
      expect(bodyText, contains('Azaman\u2019s main currency'));
      expect(bodyText, contains('converted from it'));
      expect(bodyText, isNot(contains('held in USDC')));
      await tester
          .tap(find.byKey(const ValueKey('balance-fx-fallback-disclosure-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('balance-fx-fallback-disclosure')),
          findsNothing);

      // Owner correction (2026-10-27): GHS is the app's MAIN currency —
      // the headline is the canonical balance figure and NEVER carries
      // the ≈. Only the USDC equivalent line is the estimate (converted
      // FROM the GHS balance at the display rate).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('balance-fx-equivalent-row')),
          matching: find.text('≈'),
        ),
        findsOneWidget,
        reason: 'the ≈ sits INSIDE the USDC equivalent row',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('balance-fx-headline')),
          matching: find.text('≈'),
        ),
        findsNothing,
        reason: 'the GHS headline is the canonical figure — the ≈ '
            'never marks it, on any fixture',
      );
    });

    testWidgets('NO native GHS wallet (the current live contract): an '
        'honest UNAVAILABLE headline — never a USDC-derived figure',
        (tester) async {
      final v = const BalanceCardValuation(
        // The current backend contract publishes no native-GHS wallet:
        // there is NO authoritative GHS source, so the headline may
        // never be derived from the USDC holding (owner-corrected
        // contract 2026-10-27).
        nativeGhsAvailable: null,
        availableUsdc: 50,
        balanceConfirmed: true,
        azmPoints: 0,
        rate: FxRateView(
          ghsPerUsdc: 12.03,
          kind: FxRateKind.fresh,
        ),
      ).compute();
      expect(v.availableGhsValue, isNull,
          reason: 'NO client-side derivation of GHS from USDC — ever');
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.headlineKnown, isFalse);
      await _pumpPair(tester, valuation: v);

      // The headline renders the honest unavailable dash — never a
      // fabricated GH₵ 0.00, never USDC relabelled as GHS, and never a
      // loading state.
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-headline-unavailable')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-headline-dash')),
          findsOneWidget);
      // No equivalent either: it is derived FROM the GHS balance, which
      // does not exist on this fixture.
      expect(find.byKey(const ValueKey('balance-fx-equivalent-unavailable')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-row')),
          findsNothing);
      // No estimate on screen → no ≈ and no disclosure icon.
      expect(find.text('≈'), findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-info')),
          findsNothing);
      // The rate row keeps its own informational state — a rate fact is
      // not a valuation.
      expect(find.byKey(const ValueKey('balance-fx-rate-fresh')),
          findsOneWidget);
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

    testWidgets('no rate and no fallback: the GHS headline stays KNOWN — '
        'GHS never needed a rate — and only the USDC estimate goes '
        'unavailable', (tester) async {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(kind: FxRateKind.none),
      ).compute();
      await _pumpPair(tester, valuation: v);
      expect(find.byKey(const ValueKey('balance-fx-rate-unavailable')),
          findsOneWidget);
      // The GHS headline is the native balance — it was NEVER a
      // conversion, so it needs no rate. It renders in full.
      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-headline-unavailable')),
          findsNothing);
      // Only the USDC estimate is unavailable — an honest dash in the
      // estimate slot. The REAL USDC holding never sits in that slot
      // (it is a separate concept, shown on the back face); ≈ would
      // claim a relationship that does not exist in this state.
      expect(find.byKey(const ValueKey('balance-fx-equivalent-unavailable')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-dash')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-row')),
          findsNothing);
      expect(find.text('≈'), findsNothing,
          reason: 'no rate means no equivalence claim');
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
      // The estimate slot renders the honest unavailable dash — never
      // a fabricated "≈ 0.00 USDC" conversion.
      expect(find.byKey(const ValueKey('balance-fx-equivalent-row')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-fx-equivalent-unavailable')),
          findsOneWidget);
      expect(find.textContaining('0.00 USDC'), findsNothing);
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
    testWidgets('section pages: available → committed → locked → '
        'non-cash, one section per snap step', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);

      // The pager's own children list is the complete ordered source.
      final children = (tester
              .widget<PageView>(
                  find.byKey(const ValueKey('bc-section-pager')))
              .childrenDelegate as SliverChildListDelegate)
          .children;
      final ordered = children
          .whereType<Widget>()
          .where((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('bc-section-'))
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(ordered, [
        'bc-section-available',
        'bc-section-committed',
        'bc-section-locked',
        'bc-section-noncash',
      ], reason: 'no vendor section for a non-vendor account');
      expect(ordered.last, 'bc-section-noncash',
          reason: 'NON-CASH sits after every monetary section');

      // Page 0 rows render in order with explicit native units.
      final ghs = tester.getRect(find.byKey(const ValueKey('bc-row-ghs-wallet')));
      final usdc = tester.getRect(find.byKey(const ValueKey('bc-row-usdc-held')));
      expect(ghs.top, lessThan(usdc.top));
      expect(find.textContaining('50.00 USDC', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('bc-row-vendor')), findsNothing,
          reason: 'vendor row only where relevant');
    });

    testWidgets('PRODUCTION SHAPE: every section fits its snap page under '
        'the live adapter\'s unknown-field output — no wrapped rows, no '
        'overflow', (tester) async {
      // Mirrors balance_card_valuation_provider's REAL output today: no
      // native GHS wallet, unknown vault/savings/susu, a vendor user —
      // the maximum-row shape. The GHS-wallet row's long inline
      // disclosure ("no GHS wallet on the current contract") once
      // wrapped to a second line and pushed the AVAILABLE page 9.9dp
      // past its snap page on the real Home; the row contract now
      // ellipsizes to ONE line and the full disclosure rides the
      // semantics label instead.
      await _pumpPair(
        tester,
        valuation: _saved(
          native: null,
          vault: null,
          savings: null,
          susu: null,
          vendor: true,
        ),
      );
      await _flipToBack(tester);

      // AVAILABLE: the long disclosure is present, single-line.
      expect(find.byKey(const ValueKey('bc-row-ghs-wallet')),
          findsOneWidget);
      expect(find.textContaining('no GHS wallet', findRichText: true),
          findsOneWidget);
      // The screen-reader disclosure stays FULL even though the
      // visible line ellipsizes: the semantics label carries the
      // untruncated contract.
      final ghsLabelText = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const ValueKey('bc-row-ghs-wallet')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(
        ghsLabelText.semanticsLabel,
        'GHS wallet · no GHS wallet on the current contract',
      );

      // Page through EVERY remaining section. Each pumpAndSettle inside
      // _pageDown throws on any RenderFlex overflow inside the fixed
      // 180dp card — COMMITTED (all-unknown rows), LOCKED, VENDOR
      // (present: vendor: true), NON-CASH.
      await _pageDown(tester); // COMMITTED
      expect(find.byKey(const ValueKey('bc-row-vaults')), findsOneWidget);
      await _pageDown(tester); // LOCKED
      expect(find.byKey(const ValueKey('bc-row-escrow')), findsOneWidget);
      await _pageDown(tester); // VENDOR
      expect(find.byKey(const ValueKey('bc-row-vendor')), findsOneWidget);
      await _pageDown(tester); // NON-CASH
      expect(find.byKey(const ValueKey('bc-section-noncash')),
          findsOneWidget);
    });

    testWidgets('escrow and dispute escrow are SEPARATE visible values on '
        'the LOCKED page', (tester) async {
      await _pumpPair(tester, valuation: _saved());
      await _flipToBack(tester);
      // Two section steps: available → committed → locked.
      await _pageDown(tester);
      await _pageDown(tester);
      expect(find.byKey(const ValueKey('bc-row-escrow')), findsOneWidget);
      expect(find.byKey(const ValueKey('bc-row-dispute-escrow')),
          findsOneWidget);
      expect(find.textContaining('4.00'), findsOneWidget);
      expect(find.textContaining('1.00'), findsOneWidget);
    });

    testWidgets('unknown Susu renders a dash — never zero; known Susu '
        'renders the amount', (tester) async {
      await _pumpPair(tester, valuation: _saved(susu: null));
      await _flipToBack(tester);
      await _pageDown(tester); // COMMITTED page
      final susuRow = find.byKey(const ValueKey('bc-row-susu'));
      expect(find.descendant(
              of: susuRow, matching: find.textContaining('not loaded yet')),
          findsOneWidget);
      expect(find.descendant(of: susuRow, matching: find.textContaining('—')),
          findsOneWidget,
          reason: 'unknown Susu renders a dash, never a zero (scoped to '
              'the Susu row — savings also dashes under the K2B-2 gate)');

      await tester.pumpWidget(const SizedBox());
      await _pumpPair(tester, valuation: _saved(susu: 5));
      await _flipToBack(tester);
      await _pageDown(tester);
      expect(find.descendant(
              of: susuRow, matching: find.textContaining('not loaded yet')),
          findsNothing);
      expect(find.descendant(
              of: susuRow, matching: find.textContaining('5.00 USDC')),
          findsOneWidget);
    });

    // K2B-2 regression — the card must not present the nominal GHS
    // goal amount as native GHS holdings or as guaranteed GHS value.
    // The fixture CARRIES a parsed savings figure (20 GHS); the gate
    // keeps it off the card: the row renders UNKNOWN (—) with a
    // truthful pointer to the Savings screen, which alone shows the
    // factual GHS-denominated goal progress under its own contract.
    testWidgets('K2B-2: savings renders UNKNOWN even when the '
        'valuation carries the parsed figure — no native-GHS or '
        'guaranteed-value suggestion', (tester) async {
      final valuation = _saved(); // savingsLockedGhs: 20 — PARSED
      expect(valuation.savingsLockedGhs, 20,
          reason: 'fixture really carries the parsed figure');
      await _pumpPair(tester, valuation: valuation);
      await _flipToBack(tester);
      await _pageDown(tester); // COMMITTED page
      final savingsRow = find.byKey(const ValueKey('bc-row-savings'));
      expect(
          find.descendant(
              of: savingsRow, matching: find.textContaining('—')),
          findsOneWidget,
          reason: 'the K2B-2 gate renders the aggregated savings '
              'amount UNKNOWN — the nominal GHS goal figure is not a '
              'displayable monetary holding this release');
      expect(
          find.descendant(
              of: savingsRow,
              matching: find.textContaining('on the Savings screen')),
          findsOneWidget,
          reason: 'the row points at the one surface that does show '
              'the factual GHS-denominated goal progress');
      expect(
          find.descendant(
              of: savingsRow, matching: find.textContaining('GHS')),
          findsNothing,
          reason: 'no GHS unit may render beside the savings dash — '
              'the row must not suggest native GHS is held');
      expect(
          find.descendant(
              of: savingsRow, matching: find.textContaining('20.00')),
          findsNothing,
          reason: 'the nominal GHS goal amount (20) must not appear '
              'on the card as a monetary amount');
      expect(
          find.descendant(
              of: savingsRow, matching: find.textContaining('USDC')),
          findsNothing,
          reason: 'no savings amount may ever render as USDC');
      expect(find.descendant(
              of: savingsRow, matching: find.textContaining('withdrawable')),
          findsNothing,
          reason: 'no withdrawable/cash inference from the goal figure');
    });

    testWidgets('vendor variants: its OWN section when relevant, absent '
        'when not — with a truthful restricted description', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      // Three steps: available → committed → locked → vendor.
      await _pageDown(tester);
      await _pageDown(tester);
      await _pageDown(tester);
      expect(find.byKey(const ValueKey('bc-row-vendor')), findsOneWidget);
      // The backend publishes no eligibility field, so the row describes
      // a fact — restricted — and claims nothing about withdrawability.
      expect(find.textContaining('unallocated · restricted'),
          findsOneWidget);
      expect(find.textContaining('withdrawable'), findsNothing,
          reason: 'withdrawability is never invented or denied');

      // Non-vendor: the section list has NO vendor page at all.
      await tester.pumpWidget(const SizedBox());
      await _pumpPair(tester, valuation: _saved(vendor: false));
      await _flipToBack(tester);
      expect(find.byKey(const ValueKey('bc-section-vendor')), findsNothing);
    });

    testWidgets('icons carry accessible semantic labels and supplement, '
        'never replace, text', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      Finder byIconSemantics(String label) => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label);
      // Page 0: the icons' semantics are in the tree, and the labels'
      // text still exists — icons supplement, never replace.
      expect(byIconSemantics('GHS wallet icon'), findsOneWidget);
      expect(byIconSemantics('USDC wallet icon'), findsOneWidget);
      expect(find.text('GHS wallet'), findsOneWidget);
      expect(find.text('USDC held'), findsOneWidget);
      // LOCKED page.
      await _pageDown(tester);
      await _pageDown(tester);
      expect(byIconSemantics('Escrow lock icon'), findsOneWidget);
      expect(byIconSemantics('Dispute escrow shield icon'), findsOneWidget);
      // VENDOR page.
      await _pageDown(tester);
      expect(byIconSemantics('Vendor storefront icon'), findsOneWidget);
      expect(find.textContaining('Vendor balance'), findsOneWidget);
      // NON-CASH page.
      await _pageDown(tester);
      expect(byIconSemantics('AZM points icon'), findsOneWidget);
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

    testWidgets('a vertical drag on the back PAGES the section breakdown '
        'WITHOUT flipping; the header stays fixed', (tester) async {
      await _pumpPair(tester, valuation: _saved(vendor: true));
      await _flipToBack(tester);
      final headerBefore = tester
          .getRect(find.byKey(const ValueKey('balance-fx-breakdown-header')));

      // Drag well past the 8px tap tolerance: the section pager steps to
      // the next section and settles (snap), it never flips the card.
      await _pageDown(tester);

      expect(find.byKey(const ValueKey('balance-fx-headline')),
          findsNothing,
          reason: 'a drag must never flip the card');
      final headerAfter = tester
          .getRect(find.byKey(const ValueKey('balance-fx-breakdown-header')));
      expect(headerAfter.top, closeTo(headerBefore.top, 0.5),
          reason: 'the outer card and its header stay stable');
      // The COMMITTED rows are now ON screen and the AVAILABLE rows are
      // out of the viewport — the pager stepped one SECTION (the
      // previous page may stay built for the peek, but it is no longer
      // visible).
      final pagerRect =
          tester.getRect(find.byKey(const ValueKey('bc-section-pager')));
      final vaultsRect =
          tester.getRect(find.byKey(const ValueKey('bc-row-vaults')));
      final ghsRect =
          tester.getRect(find.byKey(const ValueKey('bc-row-ghs-wallet')));
      expect(vaultsRect.top, greaterThanOrEqualTo(pagerRect.top));
      expect(vaultsRect.bottom, lessThanOrEqualTo(pagerRect.bottom + 6));
      expect(ghsRect.bottom, lessThan(pagerRect.top + 6),
          reason: 'the previous section has left the viewport (it now '
              'sits above it — the negative direction of a vertical '
              'pager)');
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
      final long = _saved(vendor: true, susu: 5);
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
