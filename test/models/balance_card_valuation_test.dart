// BALANCE CARD VALUATION — view-model contract tests.
//
// OWNER-CORRECTED PRODUCT CONTRACT (2026-10-27):
//   availableGhsValue       = nativeGhsAvailable   — the authoritative
//     native-GHS balance ONLY, never derived from USDC, never combined
//     with it. USDC held NEVER feeds the GHS headline.
//   availableUsdcEquivalent = availableGhsValue / displayRate — a display
//     estimate converted FROM that GHS balance, marked ≈ on the card.
// The two headline regressions this suite pins:
//   1. changes to actual USDC held do NOT affect the GHS headline;
//   2. the USDC estimate IS derived from the GHS balance (÷ rate).
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';

void main() {
  group('compute — the owner-corrected valuation semantics', () {
    test('REGRESSION: the GHS headline is native GHS ONLY — USDC held '
        'never enters it, whatever the rate', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      expect(
        v.availableGhsValue,
        100,
        reason:
            'the headline is the native-GHS balance verbatim — '
            'NOT 100 + 50 × 12.03',
      );
      expect(
        v.availableUsdcEquivalent,
        closeTo(100 / 12.03, 1e-9),
        reason: 'the equivalent is converted FROM the GHS balance',
      );
    });

    test('REGRESSION: changing actual USDC held NEVER changes the GHS '
        'headline', () {
      final noUsdc = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 0,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();
      final someUsdc = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();
      final lotsOfUsdc = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 5000,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      expect(noUsdc.availableGhsValue, 100);
      expect(
        someUsdc.availableGhsValue,
        100,
        reason: '50 USDC held must not move the GHS headline',
      );
      expect(
        lotsOfUsdc.availableGhsValue,
        100,
        reason: '5000 USDC held must not move the GHS headline',
      );
      // ...but the USDC holding passes through untouched as its own fact.
      expect(noUsdc.availableUsdc, 0);
      expect(lotsOfUsdc.availableUsdc, 5000);
    });

    test('REGRESSION: the USDC estimate is derived FROM the GHS balance '
        'at the rate — never from USDC held', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 240.60,
        availableUsdc: 500,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      expect(
        v.availableUsdcEquivalent,
        closeTo(240.60 / 12.03, 1e-9),
        reason: 'the estimate is GHS ÷ rate — NOT 500 USDC relabelled',
      );
      expect(
        v.availableUsdcEquivalent == v.availableUsdc,
        isFalse,
        reason: 'the estimate must never read as USDC actually held',
      );
      // The equivalent tracks the GHS balance, not the holding: halve
      // the GHS and the estimate halves; the holding is irrelevant.
      final half = const BalanceCardValuation(
        nativeGhsAvailable: 120.30,
        availableUsdc: 500,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();
      expect(
        half.availableUsdcEquivalent,
        closeTo(v.availableUsdcEquivalent! / 2, 1e-9),
      );
    });

    test('a GHS balance needs NO rate: the headline is known without FX; '
        'only the USDC equivalent waits for a rate', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 250,
        availableUsdc: 77,
        balanceConfirmed: true,
        rate: FxRateView(), // no rate at all
      ).compute();

      // The GHS headline is fully known without any rate — GHS is the
      // main currency; it was never a conversion.
      expect(v.availableGhsValue, 250);
      expect(v.headlineKnown, isTrue);
      // The equivalent CANNOT be derived without a rate — a zero here
      // would be a fabricated conversion, not an honest one.
      expect(v.availableUsdcEquivalent, isNull);
    });

    test('a GHS-only wallet WITH a valid rate: the equivalent is native '
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
    });

    test('NO authoritative native-GHS balance (null): the headline is '
        'honestly unavailable — never derived from USDC', () {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: null,
        availableUsdc: 500,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      expect(
        v.availableGhsValue,
        isNull,
        reason: '500 USDC × 12.03 must NOT become a GHS figure',
      );
      expect(v.availableUsdcEquivalent, isNull);
      expect(v.headlineKnown, isFalse);
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
        reason: 'only the authoritative native-GHS balance is the headline',
      );
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
      expect(
        v.availableGhsValue,
        40,
        reason: 'savings is locked, never in the headline',
      );
      expect(
        v.availableUsdcEquivalent,
        40 / 12.03,
        reason: 'the equivalent covers headline funds only',
      );
    });
  });

  group('an FX revaluation is NOT funds movement', () {
    test('a rate change moves ONLY the USDC estimate — the GHS headline '
        'and the ledger are untouched', () {
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
      // ...the GHS headline is IDENTICAL (it is not a conversion)...
      expect(
        b.availableGhsValue,
        a.availableGhsValue,
        reason: 'the native-GHS balance does not move with the rate',
      );
      // ...and only the USDC equivalent estimate moved.
      expect(
        b.availableUsdcEquivalent! / a.availableUsdcEquivalent!,
        closeTo(12.03 / 13.00, 1e-9),
      );
      // There is no deposit/withdrawal/delta field to set: the model has
      // no movement channel, so no false notification can exist.
    });

    test('structurally distinct fields stay distinct', () {
      // A fixture where the equivalent is NOT the held amount proves the
      // two figures are separate display concepts (100 GHS + 50 USDC at
      // 12.03 → equivalent 8.31 ≠ 50 held).
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.saved),
      ).compute();

      expect(v.availableUsdcEquivalent, closeTo(100 / 12.03, 1e-9));
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
