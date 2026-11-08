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
  double ghsPerUsdc = 15.5,
}) => BalanceCardValuation(
  nativeGhsAvailable: nativeGhs,
  availableUsdc: availableUsdc,
  balanceConfirmed: true,
  rate: FxRateView(ghsPerUsdc: ghsPerUsdc, kind: FxRateKind.fresh),
  availableGhsValue: nativeGhs,
  headlineMode: mode,
  headlineGhs: headlineGhs,
  headlineIsEstimate: isEstimate,
  backendUsdcEquivalent: backendUsdcEquivalent,
  spendableGhsNow: spendableGhsNow,
).compute();

Future<void> pumpPair(WidgetTester tester, BalanceCardValuation v) async {
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
                child: BalanceCardPair(valuation: v, colors: colors),
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

    test('the USDC equivalent is the backend figure, never derived', () {
      // 500 GHS at 15.5 would derive 32.26 — the backend says 60.
      final v = valuation(backendUsdcEquivalent: 60, ghsPerUsdc: 15.5);
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
}
