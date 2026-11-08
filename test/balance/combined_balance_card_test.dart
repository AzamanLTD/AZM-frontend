// test/balance/combined_balance_card_test.dart
// =============================================================================
// AZAMAN — GHANA-FIRST COMBINED BALANCE CARD (work packet 3-A)
//
// D1 is RESOLVED: balanceHeadlineMode = COMBINED_ESTIMATE. NATIVE_ONLY stays
// supported as a server-selectable alternative, never a client fallback.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/models/balance_valuation_payload.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart';
import 'package:azaman/providers/theme_provider.dart';

// ── helpers ─────────────────────────────────────────────────────────────────

Map<String, dynamic> money(String exact, num value) => {
  'exact': exact,
  'value': value,
};

Map<String, dynamic> emptyLocked() => {
  'escrowUsdc': money('0.00000000', 0),
  'disputesUsdc': money('0.00000000', 0),
  'vaultsUsdc': money('0.00000000', 0),
  'savingsGhs': money('0.00', 0),
  'committedSusuUsdc': money('0.00000000', 0),
  'vendorUnallocatedUsdc': money('0.00000000', 0),
};

Map<String, dynamic> payload({
  String nativeGhs = '500.00',
  num nativeGhsValue = 500,
  String availableUsdc = '20.00000000',
  num availableUsdcValue = 20,
  String? headlineMode,
  String? headlineGhs,
  num? headlineGhsValue,
  bool? headlineIsEstimate,
  String? spendableGhsNow,
  num? spendableGhsNowValue,
  String? usdcEquivalent = '60.00000000',
  num? usdcEquivalentValue = 60,
  String rateStatus = 'CURRENT',
  String valuationStatus = 'CURRENT',
  Map<String, dynamic>? locked,
}) {
  final m = <String, dynamic>{
    'pair': 'GHS/USDC',
    'nativeGhsAvailable': money(nativeGhs, nativeGhsValue),
    'availableUsdc': money(availableUsdc, availableUsdcValue),
    'rateStatus': rateStatus,
    'valuationStatus': valuationStatus,
    'usdcTransactionGateOpen': true,
    'locked': locked ?? emptyLocked(),
    'nonCash': {'azmPoints': money('0.00', 0)},
  };
  if (headlineMode != null) m['headlineMode'] = headlineMode;
  if (headlineGhs != null) {
    m['headlineGhs'] = money(headlineGhs, headlineGhsValue ?? 0);
  }
  if (headlineIsEstimate != null) m['headlineIsEstimate'] = headlineIsEstimate;
  if (spendableGhsNow != null) {
    m['spendableGhsNow'] = money(spendableGhsNow, spendableGhsNowValue ?? 0);
  }
  if (usdcEquivalent != null) {
    m['usdcEquivalent'] = money(usdcEquivalent, usdcEquivalentValue ?? 0);
  }
  return m;
}

BalanceCardValuation valuation({
  double? nativeGhs = 500,
  double availableUsdc = 20,
  BalanceHeadlineMode mode = BalanceHeadlineMode.combinedEstimate,
  double? headlineGhs = 810,
  bool isEstimate = true,
  double? backendUsdcEquivalent = 60,
  double? spendableGhsNow = 500,
  // The ONE canonical rate for this fixture: 810 / 13.5 == 60 exactly, so a
  // native headline, the rate and the backend equivalent all agree.
  double? ghsPerUsdc = 13.5,
  FxRateKind rateKind = FxRateKind.fresh,
  double escrowLocked = 5,
  double disputeEscrow = 2,
  double? vaultLocked = 7,
  double? savingsLockedGhs = 42.5,
  double? susuCommitted,
  double azmPoints = 900.75,
}) => BalanceCardValuation(
  nativeGhsAvailable: nativeGhs,
  availableUsdc: availableUsdc,
  balanceConfirmed: true,
  escrowLocked: escrowLocked,
  disputeEscrow: disputeEscrow,
  vaultLocked: vaultLocked,
  savingsLockedGhs: savingsLockedGhs,
  susuCommitted: susuCommitted,
  azmPoints: azmPoints,
  rate: FxRateView(ghsPerUsdc: ghsPerUsdc, kind: rateKind),
  availableGhsValue: nativeGhs,
  headlineMode: mode,
  headlineGhs: headlineGhs,
  headlineIsEstimate: isEstimate,
  backendUsdcEquivalent: backendUsdcEquivalent,
  spendableGhsNow: spendableGhsNow,
).compute();

/// Every string a back-face row renders, joined. Rows compose label and
/// amount spans, so `Text.data` is often null — the rendered strings are the
/// only honest evidence of what the member is actually shown.
String rowSignature(WidgetTester tester, Key row) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byKey(row), matching: find.byType(Text)),
  );
  return texts.map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('|');
}

Future<void> pumpPair(
  WidgetTester tester,
  BalanceCardValuation v, {
  // A fresh widget identity forces a fresh flip State — without it a second
  // pump would silently reuse the first card's back face.
  Key? key,
}) async {
  final colors = ThemeProvider.getColors(
    AzamanTheme.dark,
  ).withAccent(AzAccent.gold);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: BalanceCardPair(key: key, valuation: v, colors: colors),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('payload — headline block parses additively', () {
    test('combined headline, estimate flag and spendable parse verbatim', () {
      final v = BackendBalanceValuation.parse(
        payload(
          headlineMode: 'COMBINED_ESTIMATE',
          headlineGhs: '810.00',
          headlineGhsValue: 810,
          headlineIsEstimate: true,
          spendableGhsNow: '500.00',
          spendableGhsNowValue: 500,
        ),
      );
      expect(v, isNotNull);
      expect(v!.headlineMode, BackendHeadlineMode.combinedEstimate);
      expect(v.headlineGhs!.exact, '810.00');
      expect(v.headlineGhs!.value, 810);
      expect(v.headlineIsEstimate, isTrue);
      expect(v.spendableGhsNow!.exact, '500.00');
      expect(v.spendableGhsNow!.value, isNot(v.headlineGhs!.value));
    });

    test('legacy payload without the headline block is NATIVE_ONLY', () {
      final v = BackendBalanceValuation.parse(payload());
      expect(v, isNotNull);
      expect(v!.headlineMode, BackendHeadlineMode.nativeOnly);
      expect(v.headlineGhs, isNull);
      expect(v.headlineIsEstimate, isFalse);
      expect(v.spendableGhsNow, isNull);
      expect(v.nativeGhsAvailable.exact, '500.00');
      expect(v.availableUsdc.exact, '20.00000000');
    });

    test('exact decimal strings are preserved, not floatified', () {
      final v = BackendBalanceValuation.parse(
        payload(
          nativeGhs: '1234567.89',
          nativeGhsValue: 1234567.89,
          headlineMode: 'COMBINED_ESTIMATE',
          headlineGhs: '1234570.12345678',
          headlineGhsValue: 1234570.12,
        ),
      );
      expect(v!.nativeGhsAvailable.exact, '1234567.89');
      expect(v.headlineGhs!.exact, '1234570.12345678');
    });

    test('every documented valuationStatus parses', () {
      for (final raw in <String>[
        'CURRENT',
        'SAVED_FALLBACK',
        'DEMO_FALLBACK',
        'NATIVE_GHS_ONLY',
        'PARTIAL_FX_UNAVAILABLE',
        'FX_UNAVAILABLE',
      ]) {
        expect(
          BackendBalanceValuation.parse(payload(valuationStatus: raw)),
          isNotNull,
          reason: 'valuationStatus $raw must parse',
        );
      }
    });

    test('every documented rateStatus parses', () {
      for (final raw in <String>[
        'CURRENT',
        'SAVED_FALLBACK',
        'DEMO_FALLBACK',
        'UNAVAILABLE',
      ]) {
        expect(
          BackendBalanceValuation.parse(payload(rateStatus: raw)),
          isNotNull,
          reason: 'rateStatus $raw must parse',
        );
      }
    });

    test('an unknown status is a contract break, not a silent default', () {
      expect(
        BackendBalanceValuation.parse(payload(valuationStatus: 'MADE_UP')),
        isNull,
      );
      expect(
        BackendBalanceValuation.parse(payload(rateStatus: 'MADE_UP')),
        isNull,
      );
    });
  });

  // The mode decides which figure the member is shown as THEIR BALANCE, so
  // the parse is deliberately asymmetric: no mode at all is legacy, but a
  // mode the contract does not publish is a broken payload — never a quiet
  // demotion to NATIVE_ONLY, which would present a combined balance as a
  // native one.
  group('payload — headline mode is STRICT', () {
    test('no mode at all keeps the legacy NATIVE_ONLY compatibility path', () {
      final v = BackendBalanceValuation.parse(payload());
      expect(v, isNotNull);
      expect(v!.headlineMode, BackendHeadlineMode.nativeOnly);
    });

    test('an explicit null mode is treated as absent, not as a break', () {
      final v = BackendBalanceValuation.parse(
        payload()..['headlineMode'] = null,
      );
      expect(v, isNotNull);
      expect(v!.headlineMode, BackendHeadlineMode.nativeOnly);
    });

    test('both published names parse', () {
      expect(
        BackendBalanceValuation.parse(
          payload(headlineMode: 'NATIVE_ONLY'),
        )!.headlineMode,
        BackendHeadlineMode.nativeOnly,
      );
      expect(
        BackendBalanceValuation.parse(
          payload(headlineMode: 'COMBINED_ESTIMATE'),
        )!.headlineMode,
        BackendHeadlineMode.combinedEstimate,
      );
    });

    test('case is tolerated — the wire enum is published uppercase', () {
      expect(
        BackendBalanceValuation.parse(
          payload(headlineMode: 'combined_estimate'),
        )!.headlineMode,
        BackendHeadlineMode.combinedEstimate,
      );
    });

    test('an UNKNOWN mode rejects the payload — never a silent default', () {
      final v = BackendBalanceValuation.parse(
        payload(headlineMode: 'COMBINED_GUESS'),
      );
      expect(
        v,
        isNull,
        reason: 'an unrecognised mode must not become NATIVE_ONLY',
      );
    });

    test('an empty or padded mode rejects the payload', () {
      expect(BackendBalanceValuation.parse(payload(headlineMode: '')), isNull);
      expect(
        BackendBalanceValuation.parse(
          payload(headlineMode: ' COMBINED_ESTIMATE '),
        ),
        isNull,
        reason: 'a padded value is not a name the backend published',
      );
    });

    test('a MALFORMED (non-string) mode rejects the payload', () {
      for (final bad in <Object>[
        42,
        true,
        1.5,
        <String>[],
        <String, dynamic>{},
      ]) {
        final raw = payload()..['headlineMode'] = bad;
        expect(
          BackendBalanceValuation.parse(raw),
          isNull,
          reason: 'headlineMode=$bad must not parse',
        );
      }
    });

    test('a rejected mode means NO valuation at all, not a degraded one', () {
      // The failure is total on purpose: a caller must fall back to its own
      // honest unknown state rather than render a mislabelled balance.
      final v = BackendBalanceValuation.parse(
        payload(headlineMode: 'NATIVE_ISH', headlineGhs: '810.00'),
      );
      expect(v, isNull);
    });
  });

  group('headline — server-authoritative, never recomputed', () {
    test('COMBINED_ESTIMATE leads with the backend headline', () {
      final v = valuation(headlineGhs: 810);
      expect(v.effectiveHeadlineGhs, 810);
      expect(v.headlineApprox, isTrue);
    });

    test(
      'COMBINED_ESTIMATE with USDC only still uses the backend headline',
      () {
        final v = valuation(nativeGhs: 0, headlineGhs: 310, availableUsdc: 20);
        expect(v.effectiveHeadlineGhs, 310);
      },
    );

    test('NATIVE_ONLY ignores the combined field', () {
      final v = valuation(
        mode: BalanceHeadlineMode.nativeOnly,
        headlineGhs: 810,
        nativeGhs: 500,
      );
      expect(v.effectiveHeadlineGhs, 500);
      expect(v.headlineApprox, isFalse);
    });

    test('mode change does not alter the underlying bucket values', () {
      final combined = valuation(mode: BalanceHeadlineMode.combinedEstimate);
      final native = valuation(mode: BalanceHeadlineMode.nativeOnly);
      expect(combined.nativeGhsAvailable, native.nativeGhsAvailable);
      expect(combined.availableUsdc, native.availableUsdc);
    });

    test('combined mode with a missing headline degrades to native GHS', () {
      final v = valuation(headlineGhs: null);
      expect(v.effectiveHeadlineGhs, 500);
      expect(v.headlineApprox, isFalse);
    });

    test('≈ follows the server flag, not the presence of USDC', () {
      expect(
        valuation(isEstimate: false, availableUsdc: 20).headlineApprox,
        isFalse,
      );
      expect(
        valuation(isEstimate: true, availableUsdc: 20).headlineApprox,
        isTrue,
      );
    });

    test('zero USDC with a non-estimate headline shows no ≈', () {
      final v = valuation(
        availableUsdc: 0,
        headlineGhs: 500,
        isEstimate: false,
      );
      expect(v.headlineApprox, isFalse);
      expect(v.effectiveHeadlineGhs, 500);
    });

    test('the USDC equivalent is the backend figure and agrees with the '
        'one canonical rate', () {
      // The fixture is COHERENT: 810 GHS at the canonical 13.5 rate is
      // exactly the 60 USDC the backend published. Both amounts agree at
      // ONE rate, and the card shows the backend's number verbatim rather
      // than re-deriving it.
      final v = valuation(backendUsdcEquivalent: 60, ghsPerUsdc: 13.5);
      expect(
        810 / 13.5,
        closeTo(60, 1e-9),
        reason: 'the fixture itself must not disagree',
      );
      expect(v.availableUsdcEquivalent, 60);
      expect(v.effectiveHeadlineGhs, 810);
    });

    test('a stale display rate never overrides the backend equivalent', () {
      // Deliberate divergence: at a STALE 15.5 a derivation would give
      // ~52.26, but the backend's 60 still stands. This is the failure mode
      // the authoritative figure exists to eliminate.
      final v = valuation(backendUsdcEquivalent: 60, ghsPerUsdc: 15.5);
      expect(810 / 15.5, isNot(closeTo(60, 0.5)));
      expect(v.availableUsdcEquivalent, 60);
    });

    test('combined mode without a backend equivalent derives NOTHING', () {
      final v = valuation(backendUsdcEquivalent: null, ghsPerUsdc: 15.5);
      expect(v.availableUsdcEquivalent, isNull);
    });

    test('NATIVE_ONLY keeps the legacy derivation for legacy consumers', () {
      final v = valuation(
        mode: BalanceHeadlineMode.nativeOnly,
        backendUsdcEquivalent: null,
        nativeGhs: 155,
        ghsPerUsdc: 15.5,
      );
      expect(v.availableUsdcEquivalent, closeTo(10, 0.0001));
    });
  });

  group('spendability and locked funds', () {
    test('spendableGhsNow is never replaced by the combined headline', () {
      final v = valuation(headlineGhs: 810, spendableGhsNow: 500);
      expect(v.spendableGhsNow, 500);
      expect(v.effectiveHeadlineGhs, 810);
      expect(v.spendableGhsNow, isNot(v.effectiveHeadlineGhs));
    });

    test('approximate USDC value is not added to spendable GHS', () {
      final v = valuation(
        nativeGhs: 500,
        availableUsdc: 20,
        headlineGhs: 810,
        spendableGhsNow: 500,
      );
      expect(v.spendableGhsNow, 500);
      expect(v.spendableGhsNow, lessThan(v.effectiveHeadlineGhs!));
    });

    test('locked savings, escrow and disputes never reach the headline', () {
      final locked = emptyLocked()
        ..['escrowUsdc'] = money('900.00000000', 900)
        ..['disputesUsdc'] = money('800.00000000', 800)
        ..['savingsGhs'] = money('700.00', 700);
      final v = BackendBalanceValuation.parse(
        payload(
          headlineMode: 'COMBINED_ESTIMATE',
          headlineGhs: '810.00',
          headlineGhsValue: 810,
          headlineIsEstimate: true,
          locked: locked,
        ),
      );
      expect(v!.headlineGhs!.value, 810);
      expect(v.locked.escrowUsdc.value, 900);
      expect(v.locked.disputesUsdc.value, 800);
      expect(v.locked.savingsGhs.value, 700);
      expect(v.headlineGhs!.value, isNot(810 + 900 + 800 + 700));
    });
  });

  group('widget — front face', () {
    testWidgets('combined estimate renders a GH₵ headline with ≈', (t) async {
      await pumpPair(t, valuation(headlineGhs: 810, isEstimate: true));
      expect(find.byKey(const ValueKey('balance-fx-headline')), findsOneWidget);
      expect(find.textContaining('≈'), findsWidgets);
      // The semantics must say ESTIMATE, not merely draw a glyph.
      expect(
        find.bySemanticsLabel(RegExp('Estimated available balance')),
        findsWidgets,
      );
    });

    testWidgets('native-only headline is not announced as an estimate', (
      t,
    ) async {
      await pumpPair(
        t,
        valuation(
          mode: BalanceHeadlineMode.nativeOnly,
          headlineGhs: 810,
          nativeGhs: 500,
        ),
      );
      final headline = find.byKey(const ValueKey('balance-fx-headline'));
      expect(headline, findsOneWidget);
    });
  });

  // ── The BACK face. The combined estimate is a FRONT-FACE presentation of
  // one number; it must never reach the breakdown, where every holding is
  // shown in the unit it is actually denominated in.
  group('widget — back face', () {
    Finder rowText(Key row, String containing) => find.descendant(
      of: find.byKey(row),
      matching: find.textContaining(containing),
    );

    Future<void> flipToBack(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('balance-pair-flip-listener')));
      await t.pump();
      await t.pumpAndSettle();
    }

    /// The breakdown shows ONE section at a time; its pages are built
    /// lazily, so a section must be reached before it can be judged.
    Future<void> pageDown(WidgetTester t) async {
      final pager = find.byKey(const ValueKey('bc-section-pager'));
      final extent = t.getRect(pager).height * 0.86;
      await t.drag(pager, Offset(0, -(extent * 0.75)));
      await t.pumpAndSettle();
    }

    testWidgets('GHS wallet and USDC holdings stay separate, in their own '
        'native units, with the combined headline nowhere on the face', (
      t,
    ) async {
      await pumpPair(
        t,
        valuation(
          nativeGhs: 500,
          availableUsdc: 20,
          headlineGhs: 810,
          spendableGhsNow: 500,
          backendUsdcEquivalent: 60,
        ),
      );
      await flipToBack(t);

      // The faces are exclusive: the front headline is not painted behind.
      expect(
        find.byKey(const ValueKey('balance-fx-headline')),
        findsNothing,
        reason: 'flipping replaces the front face',
      );

      // Two SEPARATE holdings, each in the unit it is held in.
      expect(
        rowText(const ValueKey('bc-row-ghs-wallet'), '500.00'),
        findsOneWidget,
        reason: 'the GHS wallet row keeps the native GHS figure',
      );
      expect(
        rowText(const ValueKey('bc-row-usdc-held'), '20.00 USDC'),
        findsOneWidget,
        reason: 'the USDC row keeps the USDC holding, in USDC',
      );

      // The combined figure is NOT substituted for either holding.
      expect(
        find.textContaining('810'),
        findsNothing,
        reason: 'the combined headline belongs to the front face only',
      );
      expect(
        find.textContaining('60.00'),
        findsNothing,
        reason: 'the backend equivalent is not a holding either',
      );
    });

    testWidgets('locked breakdowns stay in native units and are never '
        'converted or folded into the headline', (t) async {
      await pumpPair(
        t,
        valuation(
          nativeGhs: 500,
          availableUsdc: 20,
          headlineGhs: 810,
          backendUsdcEquivalent: 60,
          escrowLocked: 5,
          disputeEscrow: 2,
          vaultLocked: 7,
        ),
      );
      await flipToBack(t);

      // COMMITTED: the vault holding.
      await pageDown(t);
      expect(
        rowText(const ValueKey('bc-row-vaults'), '7.00 USDC'),
        findsOneWidget,
      );

      // LOCKED: escrow and dispute escrow, each its own native figure.
      await pageDown(t);
      expect(
        rowText(const ValueKey('bc-row-escrow'), '5.00 USDC'),
        findsOneWidget,
        reason: 'escrow renders the locked USDC it actually holds',
      );
      expect(
        rowText(const ValueKey('bc-row-dispute-escrow'), '2.00 USDC'),
        findsOneWidget,
      );

      // Nothing on the locked or committed pages was converted to GHS.
      expect(find.textContaining('GH₵'), findsNothing);
    });

    testWidgets('the honest savings gate holds: no monetary value while the '
        'denomination/backing contract is unresolved', (t) async {
      await pumpPair(t, valuation(savingsLockedGhs: 42.5, susuCommitted: null));
      await flipToBack(t);
      await pageDown(t);

      expect(
        rowText(const ValueKey('bc-row-savings'), '—'),
        findsOneWidget,
        reason: 'unknown is a dash, never a fabricated figure',
      );
      expect(
        rowText(const ValueKey('bc-row-savings'), 'on the Savings screen'),
        findsOneWidget,
        reason: 'the row points at the surface that does show the fact',
      );
      expect(
        find.textContaining('42.5'),
        findsNothing,
        reason: 'the parsed aggregate is not shown as a holding',
      );
    });

    testWidgets('the breakdown is identical in both headline modes — the '
        'mode never rewrites a holding', (t) async {
      await pumpPair(
        t,
        valuation(
          mode: BalanceHeadlineMode.combinedEstimate,
          headlineGhs: 810,
          backendUsdcEquivalent: 60,
        ),
      );
      await flipToBack(t);
      final available = rowSignature(t, const ValueKey('bc-row-ghs-wallet'));
      final usdc = rowSignature(t, const ValueKey('bc-row-usdc-held'));
      await pageDown(t);
      final vaults = rowSignature(t, const ValueKey('bc-row-vaults'));

      await pumpPair(
        t,
        valuation(
          mode: BalanceHeadlineMode.nativeOnly,
          headlineGhs: 810,
          backendUsdcEquivalent: 60,
        ),
        key: const ValueKey('native-only-pair'),
      );
      await flipToBack(t);
      expect(rowSignature(t, const ValueKey('bc-row-ghs-wallet')), available);
      expect(rowSignature(t, const ValueKey('bc-row-usdc-held')), usdc);
      await pageDown(t);
      expect(rowSignature(t, const ValueKey('bc-row-vaults')), vaults);
    });
  });

  // ── PARTIAL_FX_UNAVAILABLE: the case where the backend could NOT fold the
  // USDC holding into the headline. The honest answer is the native GHS
  // balance plus a stated absence — never a client-side conversion.
  group('widget — PARTIAL_FX_UNAVAILABLE front face', () {
    test('the wire status parses to a native headline with no equivalent', () {
      final v = BackendBalanceValuation.parse(
        payload(
          headlineMode: 'COMBINED_ESTIMATE',
          headlineGhs: '500.00',
          headlineGhsValue: 500,
          headlineIsEstimate: false,
          usdcEquivalent: null,
          rateStatus: 'UNAVAILABLE',
          valuationStatus: 'PARTIAL_FX_UNAVAILABLE',
        ),
      );
      expect(v, isNotNull);
      expect(v!.headlineMode, BackendHeadlineMode.combinedEstimate);
      expect(v.headlineGhs!.value, 500);
      expect(v.headlineIsEstimate, isFalse);
      expect(v.usdcEquivalent, isNull);
      expect(v.rateStatus, BackendRateStatus.unavailable);
      expect(v.valuationStatus, BackendValuationStatus.partialFxUnavailable);
    });

    testWidgets('the native GHS headline stays, nothing is invented, and the '
        'gap is stated', (t) async {
      final v = valuation(
        mode: BalanceHeadlineMode.combinedEstimate,
        nativeGhs: 500,
        availableUsdc: 20,
        // The backend could not produce a combined figure, so the headline
        // is the native balance and is NOT flagged as an estimate.
        headlineGhs: 500,
        isEstimate: false,
        backendUsdcEquivalent: null,
        spendableGhsNow: 500,
        ghsPerUsdc: null,
        rateKind: FxRateKind.none,
      );
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.headlineApprox, isFalse);

      await pumpPair(t, v);

      // 1. The native GHS headline is still visible.
      expect(find.byKey(const ValueKey('balance-fx-headline')), findsOneWidget);
      expect(find.textContaining('500'), findsWidgets);

      // 2. No USDC contribution is invented: no ≈, no equivalent figure.
      expect(
        find.byKey(const ValueKey('balance-fx-equivalent-row')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('balance-fx-equivalent-approx')),
        findsNothing,
      );
      expect(find.textContaining('≈'), findsNothing);

      // 3. The unavailable equivalent is stated, not silently blank.
      expect(
        find.byKey(const ValueKey('balance-fx-equivalent-unavailable')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('unavailable')), findsWidgets);
    });
  });
}
