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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  // ===========================================================================
  // WIDGET BATTERY — narrow screens and large amounts (D1 final gate).
  //
  // NativeAmountText is a ONE-LINE Text.rich with ellipsis. Ellipsis eats the
  // trailing span first — under a GHS preference the trailing span is the
  // NATIVE USDC amount, under a USDC preference it is the ESTIMATE CAVEAT.
  // Losing either is a financial display lie. The widget must therefore keep
  // both parts verbatim at any width: single line when it fits, wrap when it
  // does not. These tests attack it with seven-figure amounts at 320dp/360dp
  // under BOTH preferences, plus the stale-rate and recorded tails.
  // ===========================================================================

  group('NativeAmountText narrow-screen honesty', () {
    String allText(WidgetTester tester) {
      final parts = <String>[];
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        parts.add(t.data ?? '');
      }
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            parts.add(span.text ?? '');
            span.children?.forEach(walk);
          }
        }
        walk(rich.text);
      }
      return parts.join(' ');
    }

    Widget narrowBody(Widget child) => Padding(
          padding: const EdgeInsets.all(16),
          child: Align(alignment: Alignment.topLeft, child: child),
        );

    Future<void> pumpBody(
      WidgetTester tester, {
      required double width,
      required DisplayCurrency pref,
      required Widget child,
    }) async {
      final c = ProviderContainer()
        ..read(currencyProvider.notifier).state = pref;
      addTearDown(c.dispose);
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(home: Scaffold(body: narrowBody(child))),
        ),
      );
      await tester.pump();
    }

    for (final width in [320.0, 360.0]) {
      for (final pref in DisplayCurrency.values) {
        testWidgets(
            'large amount at ${width.toInt()}dp, ${pref.name} preference: '
            'native amount AND estimate survive verbatim',
            (tester) async {
          await pumpBody(tester,
              width: width,
              pref: pref,
              child: NativeAmountText(
                amountUsdc: 1234567.89,
                snapshotOverride: _fresh(15.38),
              ));
          final text = allText(tester);
          // The amount of record, verbatim and complete.
          expect(text, contains('1,234,567.89'));
          expect(text, contains('USDC'));
          // The GHS figure, verbatim, and its caveat, never truncated.
          expect(text, contains('GH\u20b5'));
          expect(text, contains('18,987,654.15'));
          expect(text, contains('estimate'));
          // Nothing was ellipsized away.
          expect(text, isNot(contains('\u2026')));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('stale rate at 320dp: the unavailable notice is never '
        'truncated', (tester) async {
      await pumpBody(tester,
          width: 320,
          pref: DisplayCurrency.ghs,
          child: const NativeAmountText(amountUsdc: 1234567.89));
      final text = allText(tester);
      expect(text, contains('1,234,567.89 USDC'));
      expect(text, contains('GHS equivalent unavailable'));
      expect(text, isNot(contains('\u2026')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('recorded equivalent at 320dp: both figures and the label '
        'survive', (tester) async {
      await pumpBody(tester,
          width: 320,
          pref: DisplayCurrency.ghs,
          child: NativeAmountText(
            amountUsdc: 1234567.89,
            recordedGhs: 15333876.90,
            snapshotOverride: _fresh(15.38),
          ));
      final text = allText(tester);
      expect(text, contains('15,333,876.90'));
      expect(text, contains('recorded equivalent'));
      expect(text, contains('1,234,567.89 USDC'));
      expect(text, isNot(contains('\u2026')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('normal amount that fits keeps the designed single line',
        (tester) async {
      // The Ahem test font is wider than production Inter, so a short
      // amount in a small style is used to prove the SINGLE-LINE path is
      // kept when the composed line fits — the wrap is a fallback, not a
      // default.
      await pumpBody(tester,
          width: 390,
          pref: DisplayCurrency.ghs,
          child: NativeAmountText(
            amountUsdc: 0.5,
            snapshotOverride: _fresh(15.38),
            style: const TextStyle(fontSize: 8),
          ));
      final text = allText(tester);
      expect(text, contains('\u00b7'));
      expect(tester.takeException(), isNull);
    });
  });
}
