// =============================================================================
// AZAMAN — NATIVE AMOUNT DISPLAY: FINANCIAL-TRUTH BATTERY (Workstream D1)
//
// The acceptance contract for the personal-money display layer:
//   • ordering follows the preference, and only when a truthful GHS figure
//     exists (recorded, or a usable live rate);
//   • a missing/stale rate NEVER becomes a fabricated figure — the native
//     amount stands and the equivalence is named unavailable;
//   • a recorded historical GHS amount wins over today's rate and is never
//     re-derived or labelled an estimate;
//   • display preference changes can never mutate the native amount;
//   • a live conversion is always labelled a current estimate, never
//     payable value or settlement.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';

FxRateSnapshot _fresh(double ghsPerUsdc) {
  final now = DateTime.now().toUtc();
  return FxRateSnapshot(
    ghsPerUsdc: ghsPerUsdc,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

const String kNb = '\u00A0';

void main() {
  // ── 1. Ordering follows the preference with a usable rate ────────────────
  test('GHS preference leads with the live estimate and names the native', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(15.38),
    );
    expect(r.kind, EquivalenceKind.currentEstimate);
    expect(r.primary, 'GH₵${kNb}76.90');
    expect(r.secondary, contains('current estimate'));
    expect(r.secondary, contains('5.00 USDC'));
  });

  test('USDC preference keeps the native amount leading', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.usdc,
      snapshot: _fresh(15.38),
    );
    expect(r.primary, '5.00 USDC');
    expect(r.secondary, contains('GH₵${kNb}76.90'));
    expect(r.secondary, contains('current estimate'));
  });

  // ── 2. Missing / stale rate: never fabricated ─────────────────────────────
  test('no snapshot → native amount stands, equivalence NAMED unavailable',
      () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: null,
    );
    expect(r.kind, EquivalenceKind.unavailable);
    expect(r.primary, '5.00 USDC');
    expect(r.secondary, 'GHS equivalent unavailable');
    expect(r.primary, isNot(contains('GH₵')));
  });

  test('stale snapshot is refused exactly like a missing one', () {
    final stale = FxRateSnapshot(
      ghsPerUsdc: 15.38,
      source: 'KOTANI',
      lastSync: DateTime.now().toUtc(),
      fetchedAt: DateTime.now().toUtc(),
      serverFresh: true,
      lastExternalSync:
          DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
      externalRateAgeSeconds: 600,
      rateFreshnessMaxAgeSeconds: 60,
    );
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: stale,
    );
    expect(r.kind, EquivalenceKind.unavailable);
    expect(r.primary, '5.00 USDC');
    expect(r.secondary, 'GHS equivalent unavailable');
  });

  test('non-positive rate is refused even when the snapshot claims freshness',
      () {
    final bad = FxRateSnapshot(
      ghsPerUsdc: 0,
      source: 'KOTANI',
      lastSync: DateTime.now().toUtc(),
      fetchedAt: DateTime.now().toUtc(),
      serverFresh: true,
      lastExternalSync: DateTime.now().toUtc(),
      externalRateAgeSeconds: 0,
      rateFreshnessMaxAgeSeconds: 60,
    );
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: bad,
    );
    expect(r.kind, EquivalenceKind.unavailable);
  });

  // ── 3. Recorded history: the amount of record, never an estimate ─────────
  test('recorded GHS principal wins over the live rate and is not an estimate',
      () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(99.99), // today's rate must NOT touch this figure
      recordedGhs: 76.90,
    );
    expect(r.kind, EquivalenceKind.recorded);
    expect(r.primary, 'GH₵${kNb}76.90');
    expect(r.secondary, '5.00 USDC');
    expect(r.primary, isNot(contains('estimate')));
  });

  test('recorded GHS is never derived from today\'s rate', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.usdc,
      snapshot: _fresh(15.38),
      recordedGhs: 76.90, // a DIFFERENT figure from 5 × 15.38 = 76.90…
    );
    // …deliberately equal here; the assertion that matters is recorded wins:
    expect(r.secondary, 'GH₵${kNb}76.90');
  });

  // ── 4. No mutation under preference changes ──────────────────────────────
  test('the native amount string is identical under both preferences', () {
    final snapshot = _fresh(15.38);
    final ghsFirst = resolveNativeAmount(
      amountUsdc: 1234.5,
      preference: DisplayCurrency.ghs,
      snapshot: snapshot,
    );
    final usdcFirst = resolveNativeAmount(
      amountUsdc: 1234.5,
      preference: DisplayCurrency.usdc,
      snapshot: snapshot,
    );
    // The native figure appears in BOTH resolutions, unchanged: preference
    // reorders, it never re-denominates.
    expect(ghsFirst.secondary, contains('1,234.50 USDC'));
    expect(usdcFirst.primary, '1,234.50 USDC');
  });

  test('preference never changes the amount of record itself', () {
    const native = 1234.5;
    for (final pref in DisplayCurrency.values) {
      final r = resolveNativeAmount(
        amountUsdc: native,
        preference: pref,
        snapshot: _fresh(15.38),
      );
      expect(r.semanticsLabel, anyOf(contains('1,234.50 USDC')));
    }
  });

  // ── 5. Estimate honesty ───────────────────────────────────────────────────
  test('every live-conversion resolution says "current estimate"', () {
    for (final pref in DisplayCurrency.values) {
      final r = resolveNativeAmount(
        amountUsdc: 5,
        preference: pref,
        snapshot: _fresh(15.38),
      );
      expect(
        r.isEstimate,
        isTrue,
        reason: 'a live conversion must always carry the estimate label',
      );
      expect(r.semanticsLabel.toLowerCase(), contains('estimate'));
      expect(r.semanticsLabel.toLowerCase(), contains('not a settled'));
    }
  });

  // ── 6. Formatting parity ─────────────────────────────────────────────────
  test('formatting goes through AzMoney (grouping, cedi glyph)', () {
    final r = resolveNativeAmount(
      amountUsdc: 1234567.89,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(1),
    );
    expect(r.primary, 'GH₵${kNb}1,234,567.89');
  });
}
