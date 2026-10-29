// =============================================================================
// AZAMAN — COMPACT CARD TRANSFER: WORKSTREAM C ACCEPTANCE SUITE (2026-10-20)
//
// The focused acceptance tests for the compact redesign, on top of the
// contract suite (card_transfer_test.dart):
//
//   1. ROUTE-ENTRY ANIMATION — the wallet-to-transfer entrance plays ONCE
//      on route entry, settles, and NEVER replays on tab changes or
//      provider-driven rebuilds. Reduced motion lands on the end state
//      with no motion at all.
//   2. CURRENCY PREVIEW TRUTH — GHS-first default entry, the honestly-
//      labelled USDC rail equivalent at a pinned rate, the fail-closed
//      wheel switch, the no-rate degradation (named unavailable, never
//      fabricated), and the honest review pairing (preview, never a
//      settlement claim).
//   3. CLEARANCE — the keypad and the review CTA stay fully usable above
//      the bottom edge at every tested surface, including large insets
//      and large text.
//   4. THE DEMO-ONLY GATE — no surface ever claims a GHS settlement or
//      an executed transfer.
// =============================================================================

import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/card_transfer_screen.dart';
import 'package:azaman/widgets/card_transfer/compact_card_pair.dart';
import 'package:azaman/widgets/amount_keypad.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoRouter _router({double? fxRateOverride}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: AzRoutes.cardTransfer,
        builder: (context, state) =>
            CardTransferScreen(fxRateOverride: fxRateOverride),
      ),
    ],
  );
}

Widget _app(
  ProviderContainer container,
  GoRouter router, {
  bool reduceMotion = false,
  double textScale = 1.0,
  EdgeInsets? mediaPadding,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
          padding: mediaPadding,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: router,
    ),
  );
}

ProviderContainer _container({double? balance}) {
  final container = ProviderContainer(
    overrides: [
      balanceDataProvider.overrideWith(
        (ref) => BalanceData(availableBalance: balance ?? 100),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester, {
  Size surface = const Size(400, 890),
  bool reduceMotion = false,
  double? fxRateOverride,
  double textScale = 1.0,
  EdgeInsets? mediaPadding,
  bool settleEntrance = true,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _router(fxRateOverride: fxRateOverride);
  await tester.pumpWidget(
    _app(
      _container(),
      router,
      reduceMotion: reduceMotion,
      textScale: textScale,
      mediaPadding: mediaPadding,
    ),
  );
  router.go(AzRoutes.cardTransfer);
  // GoRouter processes the navigation on the first pump and mounts the
  // page on the next — the contract harness's established rhythm.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  if (settleEntrance) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _tapKey(WidgetTester tester, String label) async {
  final cell = find.descendant(
    of: find.byType(AmountKeypad),
    matching: label == 'del'
        ? find.byIcon(Icons.backspace_outlined)
        : find.text(label),
  );
  await tester.tap(cell.first);
  await tester.pump();
}

CardTransferEntranceState _entrance(WidgetTester tester) =>
    tester.state(find.byType(CardTransferEntrance));

void main() {
  setUpAll(() {
    // ThemeProvider/currency constructors read SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  // ── 1. ROUTE-ENTRY ANIMATION ─────────────────────────────────────────────

  group('the wallet-to-transfer entrance', () {
    testWidgets('plays once, on route entry', (tester) async {
      await _pump(tester, settleEntrance: false);

      // MID-ENTRANCE on the first frames: the pair is rising out of the
      // wallet and has NOT yet settled.
      expect(
        _entrance(tester).isPlaying,
        isTrue,
        reason: 'the entrance plays on route entry',
      );
      expect(_entrance(tester).progress, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 500));
      expect(_entrance(tester).isPlaying, isFalse);
      expect(
        _entrance(tester).progress,
        1.0,
        reason: 'the pair has settled at its end state',
      );
    });

    testWidgets('never replays on tab changes or rebuilds', (tester) async {
      await _pump(tester);
      expect(_entrance(tester).progress, 1.0);

      // A direction change (an unrelated rebuild of the whole screen)
      // must not restart the entrance.
      await tester.tap(find.text('From Visa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _entrance(tester).isPlaying,
        isFalse,
        reason: 'a tab change is not a route entry',
      );
      expect(_entrance(tester).progress, 1.0);

      // And back again — still settled, never replayed.
      await tester.tap(find.text('To Visa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_entrance(tester).isPlaying, isFalse);
      expect(_entrance(tester).progress, 1.0);
    });

    testWidgets('reduced motion lands on the end state with no motion', (
      tester,
    ) async {
      await _pump(tester, reduceMotion: true, settleEntrance: false);

      final entrance = _entrance(tester);
      expect(
        entrance.progress,
        1.0,
        reason: 'reduced motion: the pair is fully arrived immediately',
      );
      expect(entrance.isPlaying, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _entrance(tester).progress,
        1.0,
        reason: 'and nothing continues to move after the first frame',
      );
    });
  });

  // ── 2. CURRENCY PREVIEW TRUTH ────────────────────────────────────────────

  group('the currency preview', () {
    testWidgets('GHS-first default entry with an honest rail preview', (
      tester,
    ) async {
      await _pump(tester, fxRateOverride: 15.38);

      // The wheel's compact face renders the cedi glyph; the picker
      // carries the full GHS option.
      expect(
        find.text('GH₵'),
        findsWidgets,
        reason: 'the wheel carries the Ghana-cedi entry option',
      );
      expect(
        tester
            .widget<CurrencyWheelToggle>(
              find.byKey(const ValueKey('card-transfer-currency-wheel')),
            )
            .selectedIndex,
        0,
        reason: 'GHS is the default entry denomination',
      );

      // 5 GH₵ at 15.38 → 0.33 USDC on the rail — explicitly a PREVIEW.
      await _tapKey(tester, '5');
      expect(find.text('5 GH₵'), findsOneWidget);
      expect(
        find.textContaining('≈ 0.33\u00A0USDC · rail denomination — preview'),
        findsOneWidget,
        reason:
            'the equivalent names the USDC rail and is labelled a '
            'preview — it never claims the cedi figure settles',
      );
    });

    testWidgets('a wheel switch converts the digits at the pinned rate', (
      tester,
    ) async {
      await _pump(tester, fxRateOverride: 15.38);
      await _tapKey(tester, '5');
      expect(find.text('5 GH₵'), findsOneWidget);

      // Drive the REAL picker gesture path a user takes.
      await tester.tap(
        find.byKey(const ValueKey('card-transfer-currency-wheel')),
      );
      // Fixed pumps: the perpetual flow lane never settles, by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final usdcItem = find.text('USDC — USD Coin');
      expect(usdcItem, findsOneWidget);
      await tester.tap(usdcItem);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 5 GH₵ → 0.33 USDC: the digits CONVERTED, never relabelled.
      expect(find.text('0.33 USDC'), findsOneWidget);
      // The round trip is honest: 0.33 USDC × 15.38 → GH₵ 5.08, labelled
      // a CURRENT ESTIMATE — never a settlement amount.
      expect(
        find.textContaining('≈ GH₵\u00A05.08 · current estimate'),
        findsOneWidget,
      );
    });

    testWidgets('no usable rate: the equivalent is NAMED unavailable, '
        'the digits stay enterable', (tester) async {
      // No override and no reachable oracle in the test environment: the
      // rate is genuinely unavailable, and the surface must degrade
      // honestly instead of fabricating a conversion.
      await _pump(tester);
      await _tapKey(tester, '5');

      expect(find.text('5 GH₵'), findsOneWidget);
      expect(
        find.text('USDC rail equivalent unavailable'),
        findsOneWidget,
        reason:
            'an unusable rate must never become a silent zero or a '
            'fabricated figure',
      );

      // The fail-closed switch: with no rate, a GHS→USDC switch of a
      // NON-EMPTY amount is REFUSED — the digits are never relabelled.
      await tester.tap(
        find.byKey(const ValueKey('card-transfer-currency-wheel')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('USDC — USD Coin'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('5 GH₵'),
        findsOneWidget,
        reason: 'fail-closed: the entry keeps its denomination',
      );
      expect(
        find.byKey(const ValueKey('card-transfer-entry-error')),
        findsOneWidget,
        reason: 'the refusal is explained, never silent',
      );
    });

    testWidgets('the review pairing restates the rail truth and freezes it', (
      tester,
    ) async {
      await _pump(tester, fxRateOverride: 15.38);
      await _tapKey(tester, '1');
      await _tapKey(tester, '2');
      await _tapKey(tester, '.');
      await _tapKey(tester, '5');
      await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The entry amount keeps its GHS denomination; the rail pairing is
      // frozen at review-open and labelled a preview.
      expect(find.text('12.5 GH₵'), findsOneWidget);
      expect(find.text('Rail amount (preview)'), findsOneWidget);
      expect(
        find.textContaining('≈ 0.81\u00A0USDC — preview'),
        findsOneWidget,
        reason: '12.5 GH₵ / 15.38 → 0.81 USDC, frozen at review-open',
      );

      // Back to the amount: the freeze clears.
      await tester.tap(
        find.byKey(const ValueKey('card-transfer-back-to-amount')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('card-transfer-review-title')),
        findsNothing,
      );
    });

    testWidgets('no surface ever claims a GHS settlement', (tester) async {
      await _pump(tester, fxRateOverride: 15.38);
      await _tapKey(tester, '5');
      await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The Visa rail is USDC-denominated; a GHS equivalent is display
      // only. No text may claim the cedi figure settled anything.
      expect(find.textContaining('GHS settlement'), findsNothing);
      expect(find.textContaining('settled in GHS'), findsNothing);
      expect(find.textContaining('cedi settlement'), findsNothing);
    });
  });

  // ── 3. CLEARANCE ──────────────────────────────────────────────────────────

  group('clearance and responsive integrity', () {
    testWidgets('the keypad and the review CTA sit above the bottom edge', (
      tester,
    ) async {
      await _pump(tester, surface: const Size(360, 640));

      final keypad = tester.getRect(find.byType(AmountKeypad));
      expect(
        keypad.bottom,
        lessThanOrEqualTo(640),
        reason: 'the keypad must remain fully usable above the edge',
      );
      final cta = tester.getRect(
        find.byKey(const ValueKey('card-transfer-review-cta')),
      );
      expect(
        cta.bottom,
        lessThanOrEqualTo(640),
        reason: 'the primary action must remain fully usable',
      );
    });

    testWidgets('a large bottom inset keeps the keypad usable', (tester) async {
      // A floating band / IME-grade inset (240px) must not bury the
      // keypad or the CTA below the fold.
      await _pump(
        tester,
        surface: const Size(360, 800),
        mediaPadding: const EdgeInsets.only(bottom: 240),
      );

      expect(tester.takeException(), isNull);
      // With the region this tight the stage legitimately scrolls; the
      // guarantee is that NOTHING lands below the surface and the stage
      // really is scrollable, so the keypad and the CTA stay reachable.
      final keypad = tester.getRect(find.byType(AmountKeypad));
      expect(keypad.bottom, lessThanOrEqualTo(800));
      final cta = tester.getRect(
        find.byKey(const ValueKey('card-transfer-review-cta')),
      );
      expect(cta.bottom, lessThanOrEqualTo(800));
      final stageScrollable = find.ancestor(
        of: find.descendant(
          of: find.byType(CardTransferScreen),
          matching: find.byType(SingleChildScrollView),
        ),
        matching: find.byType(Scrollable),
      );
      final stagePosition = tester
          .state<ScrollableState>(stageScrollable)
          .position;
      expect(
        stagePosition.maxScrollExtent,
        greaterThan(0),
        reason:
            'the stage scrolls so the inset never buries the keypad '
            'beyond reach',
      );
      expect(
        cta.bottom - stagePosition.maxScrollExtent,
        lessThanOrEqualTo(800),
        reason: 'the review CTA scrolls fully above the bottom edge',
      );
    });

    testWidgets('large text scales without any layout exception', (
      tester,
    ) async {
      await _pump(tester, surface: const Size(360, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byType(CompactBalancePreview), findsOneWidget);
      expect(find.byType(CompactVisaPreview), findsOneWidget);
    });

    testWidgets('a short viewport scrolls the stage, never clips the tiles', (
      tester,
    ) async {
      await _pump(tester, surface: const Size(320, 540));
      expect(tester.takeException(), isNull);

      // The tiles keep their full footprint at every viewport.
      final balance = tester.getRect(
        find.byKey(const ValueKey('card-transfer-compact-balance')),
      );
      final visa = tester.getRect(
        find.byKey(const ValueKey('card-transfer-compact-visa')),
      );
      expect(balance.height, moreOrLessEquals(kCompactCardHeight, epsilon: 2));
      expect(visa.height, moreOrLessEquals(kCompactCardHeight, epsilon: 2));
    });
  });

  // ── 4. THE DEMO-ONLY GATE (focused re-pin on the compact surface) ─────────

  group('the demo-only execution gate', () {
    testWidgets('review never implies an executed transfer', (tester) async {
      await _pump(tester, fxRateOverride: 15.38);
      await _tapKey(tester, '5');
      await tester.tap(find.byKey(const ValueKey('card-transfer-review-cta')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No success receipt, no sent language, no enabled submit — ever.
      expect(find.textContaining('Nothing has been sent.'), findsOneWidget);
      expect(find.textContaining('Transfer complete'), findsNothing);
      expect(find.textContaining('sent to'), findsNothing);
      final submit = find.byKey(const ValueKey('card-transfer-submit'));
      expect(
        tester
            .widget<Semantics>(
              find.ancestor(of: submit, matching: find.byType(Semantics)).first,
            )
            .properties
            .enabled,
        isFalse,
        reason: 'submission stays structurally disabled on the demo rail',
      );
    });
  });
}
