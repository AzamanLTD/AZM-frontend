// BALANCE CARD VALUATION — view-model contract tests.
//
// The valuation semantics of the Final Balance Card Redesign (§4 of the
// product definition):
//   availableGhsValue       = nativeGhsAvailable + availableUsdc * rate
//   availableUsdcEquivalent = availableGhsValue / rate
// The backend's returned valuation is authoritative once the contract
// lands; [compute] is the honest derivation for fixtures/interim state.
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';

void main() {
  group('compute — the agreed valuation semantics', () {
    test('combined value = native GHS + (USDC held x rate)', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      expect(v.availableGhsValue, closeTo(100 + 50 * 12.03, 1e-9));
      expect(
        v.availableUsdcEquivalent,
        closeTo((100 + 50 * 12.03) / 12.03, 1e-9),
      );
    });

    test('a zero-USDC wallet needs no rate: GHS alone is the total — but '
        'without a rate its USDC equivalent is unknown, never zero', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 250,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(), // no rate at all
      ).compute();

      // The GHS headline is fully known without any rate.
      expect(v.availableGhsValue, 250);
      expect(v.headlineKnown, isTrue);
      expect(v.valuationIncomplete, isFalse);
      // The equivalent CANNOT be derived without a rate — a zero here would
      // be a fabricated conversion, not an honest one.
      expect(v.availableUsdcEquivalent, isNull);
    });

    test('a zero-USDC wallet WITH a valid rate: the equivalent is native '
        'GHS divided by the rate, not zero', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 250,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.5, kind: FxRateKind.fresh),
      ).compute();

      expect(v.availableGhsValue, 250);
      expect(v.availableUsdcEquivalent, closeTo(250 / 12.5, 1e-9));
      expect(v.headlineKnown, isTrue);
      expect(v.valuationIncomplete, isFalse);
    });

    test('a zero-zero wallet without a rate keeps an honest null '
        'equivalent — zero GHS converts to zero USDC only under a rate', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 0,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(), // no rate at all
      ).compute();

      expect(v.availableGhsValue, 0);
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.valuationIncomplete, isFalse);
    });

    test('USDC held with no valid rate → the combined total is honestly '
        'unavailable, never native-GHS-as-total', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(kind: FxRateKind.none),
      ).compute();

      expect(
        v.availableGhsValue,
        isNull,
        reason: 'no fabricated combined total without a rate',
      );
      expect(v.availableUsdcEquivalent, isNull);
      expect(
        v.valuationIncomplete,
        isTrue,
        reason:
            'known native GHS + unvaluable USDC is explicitly '
            'incomplete',
      );
    });

    test('locked, committed, savings, vendor and points NEVER feed the '
        'headline valuation', () {
      final base = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 10, kind: FxRateKind.fresh),
      ).compute();

      final withLocks = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        escrowLocked: 999,
        disputeEscrow: 999,
        vaultLocked: 999,
        savingsLockedGhs: 999,
        susuCommitted: 999,
        vendorUnallocatedUsdc: 999,
        vendorRowRelevant: true,
        azmPoints: 999999,
        rate: FxRateView(ghsPerUsdc: 10, kind: FxRateKind.fresh),
      ).compute();

      expect(
        withLocks.availableGhsValue,
        base.availableGhsValue,
        reason:
            'only backend-confirmed withdrawable funds count toward '
            'the headline',
      );
    });

    test('savings is excluded from the headline — there is no '
        'savings-withdrawable concept in the contract', () {
      final noNet = const BalanceCardValuation(
        nativeGhsAvailable: 0,
        availableUsdc: 10,
        balanceConfirmed: true,
        savingsLockedGhs: 500,
        rate: FxRateView(ghsPerUsdc: 10, kind: FxRateKind.fresh),
      ).compute();

      expect(noNet.availableGhsValue, 100, reason: '10 USDC x 10 only');
    });

    test('savings is GHS-denominated: it passes through the model '
        'untouched by any rate and never enters USDC rails', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 40,
        availableUsdc: 0,
        balanceConfirmed: true,
        savingsLockedGhs: 75.50,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      // The GHS-denominated savings value is preserved exactly: no rate
      // is ever applied to it, and it never appears as a USDC amount.
      expect(v.savingsLockedGhs, 75.50);
      expect(v.availableGhsValue, 40,
          reason: 'savings is locked, never in the headline');
      expect(v.availableUsdcEquivalent, 40 / 12.03,
          reason: 'the equivalent covers headline funds only');
    });
  });

  group('an FX revaluation is NOT funds movement', () {
    test('a rate change changes ONLY the USDC valuation component — no '
        'delta channel exists in the model', () {
      final a = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();
      final b = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 13.00, kind: FxRateKind.fresh),
      ).compute();

      // The ledger state is untouched by the rate change...
      expect(b.nativeGhsAvailable, a.nativeGhsAvailable);
      expect(b.availableUsdc, a.availableUsdc);
      expect(b.escrowLocked, a.escrowLocked);
      expect(b.savingsLockedGhs, a.savingsLockedGhs);
      // ...and only the GHS valuation of the USDC component moved.
      expect(
        b.availableGhsValue! - a.availableGhsValue!,
        closeTo(50 * (13.00 - 12.03), 1e-9),
      );
      // There is no deposit/withdrawal/delta field to set: the model has
      // no movement channel, so no false notification can exist.
    });

    test('structurally distinct fields stay distinct', () {
      // A fixture where the equivalent is NOT the held amount proves the
      // two figures are separate display concepts (100 GHS + 50 USDC at
      // 12.03 → equivalent 58.35 ≠ 50 held).
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.saved),
      ).compute();

      expect(v.availableUsdcEquivalent, closeTo(701.5 / 12.03, 1e-9));
      expect(v.availableUsdc, 50);
      expect(
        v.availableUsdcEquivalent! == v.availableUsdc,
        isFalse,
        reason: 'the equivalent must never read as USDC actually held',
      );
    });
  });

  group('rate provenance', () {
    test('fresh means fresh — no fallback flag', () {
      const rate = FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh);
      expect(rate.isFresh, isTrue);
      expect(rate.isFallback, isFalse);
    });

    test('saved and demo are both fallback states requiring disclosure', () {
      const saved = FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.saved);
      const demo = FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.demo);
      expect(saved.isFallback, isTrue);
      expect(demo.isFallback, isTrue);
    });

    test('a zero or missing rate is never a usable rate', () {
      const zero = FxRateView(ghsPerUsdc: 0, kind: FxRateKind.fresh);
      const absent = FxRateView(kind: FxRateKind.saved);
      expect(
        zero.hasRate,
        isFalse,
        reason: 'rate 0 means unavailable, never a live zero',
      );
      expect(absent.hasRate, isFalse);
    });
  });
}
