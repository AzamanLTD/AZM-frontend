// =============================================================================
// AZAMAN — WORKSTREAM D: CONVERT PRESENTATION (Binance-style From/To)
//
// The Workstream D contract on top of the honest G shell:
//   • FROM panel: asset + amount + balance info ONLY where the ledger
//     contract supports it (settled USDC side, only when the canonical
//     balance read has loaded — never fabricated).
//   • ANIMATED direction switch: subtle, reduced-motion aware, and it
//     NEVER implies money moved — digits are never relabelled, so the
//     amount CLEARS on switch.
//   • TO panel: estimated receive at the displayed rate (forward: ×
//     rate → GHS; reversed: ÷ rate → USDC), the truthful rate/freshness
//     strip, and NO fee line (no fee contract exists).
//   • Dominant bottom action stays GATED while
//     [kConvertExecutionSupported] is false — verified live false.
//   • Surface grammar: X-close top-left, pull-down-dismissible.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/currency_provider.dart'
    show FxRateSnapshot, fxRateProvider;
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/screens/wallet/convert_screen.dart';

FxRateSnapshot _usableSnapshot({double rate = 12.50}) {
  final now = DateTime.now().toUtc();
  return FxRateSnapshot(
    ghsPerUsdc: rate,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now,
    externalRateAgeSeconds: 0,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Widget _convertHarness({
  FxRateSnapshot? snapshot,
  bool balanceLoaded = false,
  double availableBalance = 987.65,
}) {
  // [balanceLoaded] false → the canonical read has NOT loaded
  // (unresolved, the honest default) and the From panel must OMIT the
  // balance line; true → loaded with that settled USDC figure. The
  // override STRUCTURE is constant across pumps (riverpod forbids
  // changing the override count between builds of one test).
  return ProviderScope(
    overrides: [
      fxRateProvider.overrideWith((ref) async => snapshot),
      balanceReadinessProvider.overrideWith(
        (ref) => balanceLoaded
            ? BalanceReadiness.loaded
            : BalanceReadiness.unresolved,
      ),
      balanceDataProvider.overrideWith(
        (ref) => BalanceData(availableBalance: availableBalance),
      ),
    ],
    child: const MaterialApp(home: ConvertScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('D1 — From/To presentation contract', () {
    testWidgets('forward direction renders USDC From and GHS To with the '
        'settled/display semantics', (tester) async {
      await tester.pumpWidget(
        _convertHarness(snapshot: _usableSnapshot(), balanceLoaded: true),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('convert_from_panel')), findsOneWidget);
      expect(find.byKey(const Key('convert_to_panel')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('convert_to_asset'))).data,
        'GHS',
        reason: 'forward direction quotes GHS as the To asset',
      );
      expect(find.text('Settled balance'), findsOneWidget);
      expect(find.text('Display currency'), findsAtLeast(1));
    });

    // NOTE: two separate tests, not two pumps in one — a StateProvider's
    // override seeds state at container creation and does NOT re-initialise
    // on a later pumpWidget, so loaded/unloaded must each get a fresh
    // binding to stay honest (not a riverpod workaround in production —
    // pure test-harness fact).
    testWidgets('balance line is OMITTED while the canonical read has not '
        'loaded — never a fabricated figure', (tester) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('convert_from_balance')),
        findsNothing,
        reason: 'an unloaded read must never fabricate a balance',
      );
    });

    testWidgets('balance line shows the settled USDC figure when loaded, '
        'and drops when the From asset becomes GHS', (tester) async {
      await tester.pumpWidget(
        _convertHarness(snapshot: _usableSnapshot(), balanceLoaded: true),
      );
      await tester.pumpAndSettle();
      final line = find.byKey(const Key('convert_from_balance'));
      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).data, contains('987.65'));

      // Reversed direction → GHS is the From asset and has NO balance to
      // disclose; the line must disappear again.
      await tester.tap(find.byKey(const Key('convert_direction_switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('convert_from_balance')),
        findsNothing,
        reason:
            'GHS is a display/quote currency — it has no settled '
            'balance to disclose in any direction',
      );
    });

    testWidgets('forward estimate math is unchanged: 5 USDC → ≈ GH₵ 62.50 '
        'GHS at the pinned rate', (tester) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('convert_amount_field')),
        '5',
      );
      await tester.pump();

      final estimate = tester
          .widget<Text>(find.byKey(const Key('convert_amount_estimate')))
          .data!;
      expect(estimate, contains('62.50'));
      expect(estimate, contains('GHS'));
    });

    testWidgets('no fee line is invented — no fee contract exists', (
      tester,
    ) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('convert_amount_field')),
        '5',
      );
      await tester.pump();

      expect(
        find.textContaining('fee'),
        findsNothing,
        reason:
            'a fee line without a fee contract is a fabricated '
            'financial fact',
      );
      expect(find.textContaining('Fee'), findsNothing);
    });
  });

  group('D2 — direction switch', () {
    testWidgets('switching direction swaps the asset roles AND clears the '
        'amount — digits are never relabelled', (tester) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('convert_amount_field')),
        '50',
      );
      await tester.pump();

      final switchButton = find.byKey(const Key('convert_direction_switch'));
      expect(switchButton, findsOneWidget);
      await tester.tap(switchButton);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('convert_to_asset'))).data,
        'USDC',
      );
      final field = tester
          .widget<TextField>(find.byKey(const Key('convert_amount_field')))
          .controller!;
      expect(
        field.text,
        isEmpty,
        reason: '50 USDC must never silently become 50 GHS',
      );
      expect(
        find.byKey(const Key('convert_amount_estimate_pending')),
        findsOneWidget,
        reason:
            'with the amount cleared the honest state is the estimate '
            'prompt, not a carried-over figure',
      );
    });

    testWidgets('reversed estimate math: 125 GHS → ≈ 10.00 USDC at the '
        'pinned rate', (tester) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('convert_direction_switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('convert_amount_field')),
        '125',
      );
      await tester.pump();

      final estimate = tester
          .widget<Text>(find.byKey(const Key('convert_amount_estimate')))
          .data!;
      expect(estimate, contains('10.00'));
      expect(estimate, contains('USDC'));
    });

    testWidgets('non-finite guards hold in the reversed direction too', (
      tester,
    ) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('convert_direction_switch')));
      await tester.pumpAndSettle();

      final controller = tester
          .widget<TextField>(find.byKey(const Key('convert_amount_field')))
          .controller!;
      controller.text = '9' * 400; // parses as Infinity — bypasses formatters
      await tester.pump();

      expect(find.byKey(const Key('convert_amount_estimate')), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(
        find.byKey(const Key('convert_amount_estimate_too_large')),
        findsOneWidget,
      );
    });

    testWidgets('the switch never implies money moved: the CTA stays inert '
        'in BOTH directions', (tester) async {
      await tester.pumpWidget(_convertHarness(snapshot: _usableSnapshot()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('convert_execution_unavailable')),
        findsOneWidget,
      );
      final cta = find.byKey(const Key('convert_cta'));
      expect(tester.widget<FilledButton>(cta).onPressed, isNull);

      await tester.tap(find.byKey(const Key('convert_direction_switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('convert_execution_unavailable')),
        findsOneWidget,
        reason: 'no direction may upgrade the gated capability',
      );
      expect(tester.widget<FilledButton>(cta).onPressed, isNull);
    });

    testWidgets('reduced motion: under disableAnimations the icon rotation '
        'settles immediately — no transit is required', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _convertHarness(snapshot: _usableSnapshot()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('convert_direction_switch')));
      await tester.pump(const Duration(milliseconds: 1));

      final rotation = tester.widget<AnimatedRotation>(
        find
            .descendant(
              of: find.byKey(const Key('convert_direction_switch')),
              matching: find.byType(AnimatedRotation),
            )
            .first,
      );
      expect(rotation.turns, 0.5);
    });
  });

  group('D3 — surface grammar', () {
    testWidgets('X-close pops the convert surface', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProviderScope(
                      overrides: [
                        fxRateProvider.overrideWith(
                          (ref) async => _usableSnapshot(),
                        ),
                      ],
                      child: const ConvertScreen(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('convert_close')), findsOneWidget);

      await tester.tap(find.byKey(const Key('convert_close')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('convert_close')),
        findsNothing,
        reason: 'the X affordance must pop the surface it closes',
      );
      expect(
        find.text('open'),
        findsOneWidget,
        reason:
            'the surface underneath is back — a real pop, not a '
            'hidden overlay',
      );
    });
  });
}
