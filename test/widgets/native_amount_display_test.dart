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

  // ── 3. Recorded history: a historical equivalent, never a principal and
  //      never an estimate; its figure GENUINELY differs from today's
  //      conversion so passing proves the recorded value was used. ──────────
  test('a recorded historical GHS equivalent wins over the live rate', () {
    // 5 × 15.38 = 76.90 is what TODAY would say; the recorded figure is
    // 69.00, so any recomputation from the live rate fails these asserts.
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(15.38), // today's rate would say GH₵76.90
      recordedGhs: 69.00, // recorded at initiation, at a DIFFERENT rate
    );
    expect(r.kind, EquivalenceKind.recorded);
    expect(r.primary, 'GH₵${kNb}69.00');
    expect(r.primary, isNot(contains('76.90')));
    expect(r.semanticsLabel, isNot(contains('76.90')));
    expect(r.primary, isNot(contains('estimate')));
  });

  test('recorded equivalent keeps the native USDC amount visible and labelled',
      () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.usdc,
      snapshot: _fresh(15.38),
      recordedGhs: 69.00,
    );
    expect(r.kind, EquivalenceKind.recorded);
    expect(r.primary, '5.00 USDC');
    expect(r.secondary, contains('GH₵${kNb}69.00'));
    expect(r.secondary, contains('recorded equivalent'));
    expect(r.secondary, isNot(contains('estimate')));
    expect(r.inlineLead, '5.00 USDC');
    expect(r.inlineTail, 'GH₵${kNb}69.00 (recorded equivalent)');
  });

  test('a recorded value is never presented as today\'s live estimate', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(15.38),
      recordedGhs: 69.00,
    );
    expect(r.semanticsLabel.toLowerCase(), contains('recorded'));
    expect(
        r.semanticsLabel.toLowerCase(), isNot(contains('current estimate')));
    expect(r.inlineLead, 'GH₵${kNb}69.00 (recorded equivalent)');
  });

  test('an invalid recorded value is ignored, never coerced', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      recordedGhs: double.nan, // invalid: refused like a missing record
    );
    expect(r.kind, EquivalenceKind.unavailable);
    expect(r.primary, '5.00 USDC');
    expect(r.primary, isNot(contains('GH₵')));
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

  // ── 5b. Inline one-line truth: both parts visible, caveat attached ───────
  test('GHS-first inline shows the estimate caveat AND the native amount', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(15.38),
    );
    expect(r.inlineLead, 'GH₵${kNb}76.90 (estimate)');
    expect(r.inlineTail, '5.00 USDC');
  });

  test('USDC-first inline carries a labelled estimate after the native', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.usdc,
      snapshot: _fresh(15.38),
    );
    expect(r.inlineLead, '5.00 USDC');
    expect(r.inlineTail, '≈ GH₵${kNb}76.90 (estimate)');
  });

  test('unavailable inline names the missing equivalence, native intact', () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: null,
    );
    expect(r.inlineLead, '5.00 USDC');
    expect(r.inlineTail, 'GHS equivalent unavailable');
  });

  test('forceNative keeps a comparison slot same-unit under GHS preference',
      () {
    final r = resolveNativeAmount(
      amountUsdc: 5,
      preference: DisplayCurrency.ghs,
      snapshot: _fresh(15.38),
      forceNative: true,
    );
    expect(r.primary, '5.00 USDC');
    expect(r.inlineLead, '5.00 USDC');
    expect(r.inlineTail, '≈ GH₵${kNb}76.90 (estimate)');
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
