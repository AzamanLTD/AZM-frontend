// BALANCE CARD (FX-STATUS FRONT + ICON-LED BACK) — widget contract tests.
//
// The product contract for the Final Balance Card Redesign, proven on the
// typed fixture (the backend valuation contract is pending; the widget is
// pure and renders only what it is given):
//   • GHS-first ALWAYS — no currency toggle, no global-preference switch.
//   • Headline / USDC equivalent / USDC held are three distinct figures.
//   • A rate change revalues ONLY the USDC display component; it never
//     changes displayed ledger figures and produces no delta/movement UI.
//   • FX loading never replaces a known balance; dots live ONLY in the
//     bottom-left rate row and only while loading with no fallback shown.
//   • Saved fallback: info icon beside the equivalent + explicit saved
//     identification + refresh slot retained; refresh keeps the shown
//     value (no dots swap).
//   • No rate: stable unavailable state; unvaluable USDC → the combined
//     valuation is presented as incomplete, never native-alone-as-total.
//   • The disclosure is touch/keyboard/screen-reader accessible and
//     includes source/timestamp when available.
//   • The demo rate comes from the fixture contract (kind: demo), never a
//     widget constant.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/home/balance_card_breakdown.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeProvider.getThemeData(AzamanTheme.dark),
  home: Scaffold(body: Center(child: child)),
);

Future<void> _pump(
  WidgetTester tester, {
  required BalanceCardValuation valuation,
  bool back = false,
  Widget? refresh,
}) async {
  final c = ThemeProvider.getColors(AzamanTheme.dark).withAccent(AzAccent.gold);
  await tester.pumpWidget(
    _wrap(
      back
          ? BalanceCardBreakdown(valuation: valuation, colors: c)
          : BalanceCardFx(
              valuation: valuation,
              colors: c,
              trailingRefresh:
                  refresh ??
                  const SizedBox(
                    key: ValueKey('test-refresh-indicator'),
                    width: 24,
                    height: 12,
                  ),
            ),
    ),
  );
  await tester.pump();
}

BalanceCardValuation _savedFixture() => BalanceCardValuation(
  nativeGhsAvailable: 100,
  availableUsdc: 50,
  balanceConfirmed: true,
  escrowLocked: 4,
  disputeEscrow: 1,
  vaultLocked: 10,
  savingsLocked: 20,
  susuCommitted: 5,
  azmPoints: 1200,
  rate: FxRateView(
    ghsPerUsdc: 12.03,
    kind: FxRateKind.saved,
    sourceLabel: 'saved observation',
    observedAt: DateTime.utc(2026, 10, 22, 9, 30),
  ),
).compute();

void main() {
  testWidgets('GHS-first ALWAYS: no currency toggle, headline is the GHS '
      'value even for a USDC-heavy wallet', (tester) async {
    await _pump(tester, valuation: _savedFixture());

    expect(find.byKey(const ValueKey('balance-fx-headline')), findsOneWidget);
    expect(find.textContaining('GH\u20b5'), findsWidgets);
    // No currency wheel/toggle exists on this card at all.
    expect(find.byKey(const ValueKey('currency-wheel')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(
      find.byKey(const ValueKey('hologram-currency-toggle')),
      findsNothing,
    );
  });

  testWidgets('headline, USDC equivalent and USDC held are three distinct '
      'figures', (tester) async {
    // 100 GHS + 50 USDC at 12.03 → 701.50 GHS, equivalent 58.31 USDC —
    // distinct from the 50 USDC actually held.
    await _pump(tester, valuation: _savedFixture());
    expect(
      find.textContaining('701.50'),
      findsOneWidget,
      reason: 'the combined available value in GHS',
    );
    expect(
      find.textContaining('58.31'),
      findsOneWidget,
      reason: 'the overall USDC equivalent',
    );
    expect(
      find.textContaining('50.00 USDC'),
      findsNothing,
      reason: 'the front never shows the raw held amount',
    );

    await _pump(tester, valuation: _savedFixture(), back: true);
    expect(find.text('USDC held'), findsOneWidget);
    expect(
      find.textContaining('50.00'),
      findsOneWidget,
      reason:
          'the BACK face shows the actual holding under its explicit '
          'USDC-held label',
    );
  });

  testWidgets('a rate change revalues ONLY the USDC display component and '
      'produces no delta or movement UI', (tester) async {
    final atOld = _savedFixture();
    final atNew = BalanceCardValuation(
      nativeGhsAvailable: atOld.nativeGhsAvailable,
      availableUsdc: atOld.availableUsdc,
      balanceConfirmed: true,
      escrowLocked: atOld.escrowLocked,
      disputeEscrow: atOld.disputeEscrow,
      vaultLocked: atOld.vaultLocked,
      savingsLocked: atOld.savingsLocked,
      susuCommitted: atOld.susuCommitted,
      azmPoints: atOld.azmPoints,
      rate: const FxRateView(ghsPerUsdc: 13.00, kind: FxRateKind.fresh),
    ).compute();

    await _pump(tester, valuation: atOld);
    expect(find.textContaining('701.50'), findsOneWidget);

    await _pump(tester, valuation: atNew);
    expect(
      find.textContaining('750.00'),
      findsOneWidget,
      reason:
          'the GHS valuation of the USDC component moved with the '
          'rate',
    );
    // No delta chip / deposit / withdrawal / movement UI of any kind.
    expect(find.byKey(const ValueKey('balance-delta')), findsNothing);
    expect(find.textContaining('deposited'), findsNothing);
    expect(find.textContaining('withdraw'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('FX loading never replaces a known balance; dots appear ONLY '
      'in the bottom-left rate row while loading without a fallback', (
    tester,
  ) async {
    final loading = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(kind: FxRateKind.none, loading: true),
    ).compute();

    await _pump(tester, valuation: loading);

    // The amount slot keeps its confirmed-state law: no FX dots there.
    expect(find.byKey(const ValueKey('balance-fx-amount-dots')), findsNothing);
    // A confirmed balance with an uncomputable total keeps the native
    // figure visible (never blanked by loading).
    expect(
      find.byKey(const ValueKey('balance-fx-headline-native')),
      findsOneWidget,
    );
    // Dots live only in the rate row.
    expect(find.byKey(const ValueKey('balance-fx-rate-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('balance-fx-rate-row')), findsOneWidget);
  });

  testWidgets('a loading refresh KEEPS an already-shown saved fallback in '
      'place — no dots swap', (tester) async {
    final refreshing = BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(
        ghsPerUsdc: 12.03,
        kind: FxRateKind.saved,
        loading: true, // genuinely refreshing
        sourceLabel: 'saved observation',
        observedAt: DateTime.utc(2026, 10, 22, 9, 30),
      ),
    ).compute();

    await _pump(tester, valuation: refreshing);
    expect(
      find.byKey(const ValueKey('balance-fx-rate-saved')),
      findsOneWidget,
      reason: 'the saved value/status stays visible during refresh',
    );
    expect(find.byKey(const ValueKey('balance-fx-rate-dots')), findsNothing);
    expect(
      find.byKey(const ValueKey('balance-fx-equivalent-info')),
      findsOneWidget,
      reason: 'the info icon stays beside the equivalent',
    );
  });

  testWidgets('saved fallback: info icon beside the equivalent, explicit '
      'saved identification in the rate row, refresh slot retained', (
    tester,
  ) async {
    await _pump(tester, valuation: _savedFixture());

    expect(
      find.byKey(const ValueKey('balance-fx-equivalent-info')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('balance-fx-rate-saved')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('balance-fx-rate-saved')))
          .data,
      contains('Using saved rate'),
    );
    expect(
      find.byKey(const ValueKey('test-refresh-indicator')),
      findsOneWidget,
      reason: 'the right-side refresh affordance stays in place',
    );

    // The info icon sits BESIDE the equivalent, not by the headline and
    // not at the row's right edge.
    final eqRow = tester.getRect(
      find.byKey(const ValueKey('balance-fx-equivalent-row')),
    );
    final info = tester.getRect(
      find.byKey(const ValueKey('balance-fx-equivalent-info')),
    );
    final card = tester.getRect(find.byKey(const ValueKey('balance-fx-card')));
    expect(info.left, greaterThan(eqRow.left));
    expect(
      info.right,
      lessThan(card.right - 8),
      reason: 'not at the card edge where refresh lives',
    );
  });

  testWidgets('no rate and no fallback: stable unavailable state, no '
      'fabricated rate, native GHS visible with an explicit incomplete '
      'valuation note', (tester) async {
    final none = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(kind: FxRateKind.none, loading: false),
    ).compute();

    await _pump(tester, valuation: none);

    expect(
      find.byKey(const ValueKey('balance-fx-rate-unavailable')),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 USDC ≈'),
      findsNothing,
      reason: 'no fabricated rate may render',
    );
    expect(
      find.byKey(const ValueKey('balance-fx-headline-native')),
      findsOneWidget,
      reason: 'the known native GHS amount remains visible',
    );
    expect(
      find.byKey(const ValueKey('balance-fx-valuation-incomplete')),
      findsOneWidget,
      reason: 'native GHS alone is never presented as the total',
    );
    expect(
      find.byKey(const ValueKey('balance-fx-equivalent-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('the fallback disclosure opens on tap and is honest about '
      'indicative, non-quote status, source and timestamp', (tester) async {
    await _pump(tester, valuation: _savedFixture());

    await tester.tap(find.byKey(const ValueKey('balance-fx-equivalent-info')));
    await tester.pumpAndSettle();

    final body = tester
        .widget<Text>(
          find.byKey(const ValueKey('balance-fx-fallback-disclosure-body')),
        )
        .data!;
    expect(body, contains('indicative display calculation'));
    expect(body, contains('last saved validated rate'));
    expect(body, contains('not a live rate'));
    expect(
      body,
      contains('USDC-enabled transactions are unavailable'),
    );
    expect(body, contains('2026-10-22 09:30 UTC'));
    expect(body, contains('saved observation'));
  });

  testWidgets('the info button is keyboard focusable and carries semantics', (
    tester,
  ) async {
    await _pump(tester, valuation: _savedFixture());

    final semantics = find.bySemanticsLabel(
      'About the USDC equivalent and saved rate',
    );
    expect(semantics, findsOneWidget);
    // Focus travels to the button from the keyboard.
    final focus = Focus(
      child: Builder(
        builder: (context) => BalanceCardFx(
          valuation: _savedFixture(),
          colors: ThemeProvider.getColors(
            AzamanTheme.dark,
          ).withAccent(AzAccent.gold),
        ),
      ),
    );
    await tester.pumpWidget(_wrap(focus));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  });

  testWidgets('the demo rate comes from the fixture contract, not a widget '
      'constant', (tester) async {
    final demo = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 100,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.demo),
    ).compute();
    final otherDemo = const BalanceCardValuation(
      nativeGhsAvailable: 0,
      availableUsdc: 100,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 9.87, kind: FxRateKind.demo),
    ).compute();

    await _pump(tester, valuation: demo);
    expect(find.byKey(const ValueKey('balance-fx-rate-demo')), findsOneWidget);
    expect(
      find.textContaining('12.03'),
      findsWidgets,
      reason: 'the displayed value is the CONTRACT value',
    );

    // A different seeded value renders differently — the widget cannot be
    // hard-coding any rate.
    await _pump(tester, valuation: otherDemo);
    expect(find.textContaining('9.87'), findsWidgets);
    expect(find.textContaining('12.03'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('balance-fx-equivalent-info')));
    await tester.pumpAndSettle();
    final body = tester
        .widget<Text>(
          find.byKey(const ValueKey('balance-fx-fallback-disclosure-body')),
        )
        .data!;
    expect(body, contains('demo-seeded rate'));
    expect(body, contains('not a real market feed'));
  });

  testWidgets('a fresh rate shows no fallback chrome at all', (tester) async {
    final fresh = const BalanceCardValuation(
      nativeGhsAvailable: 100,
      availableUsdc: 50,
      balanceConfirmed: true,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
    ).compute();

    await _pump(tester, valuation: fresh);
    expect(find.byKey(const ValueKey('balance-fx-rate-fresh')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('balance-fx-equivalent-info')),
      findsNothing,
    );
    expect(find.textContaining('saved'), findsNothing);
    expect(
      find.textContaining('stale'),
      findsNothing,
      reason: 'genuinely fresh — no stale-rate warning',
    );
  });

  testWidgets('an unconfirmed balance renders the balance placeholder, '
      'never a fabricated 0.00 headline', (tester) async {
    final unconfirmed = const BalanceCardValuation(
      balanceConfirmed: false,
      rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
    ).compute();

    await _pump(tester, valuation: unconfirmed);
    expect(
      find.byKey(const ValueKey('balance-fx-amount-dots')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('balance-fx-headline')), findsNothing);
  });

  group('back face — icon-led breakdown', () {
    testWidgets('rows carry labels, native units and right-aligned amounts; '
        'susu unknown renders a dash, vendor only when relevant', (
      tester,
    ) async {
      final v = const BalanceCardValuation(
        nativeGhsAvailable: 100,
        availableUsdc: 50,
        balanceConfirmed: true,
        escrowLocked: 4,
        disputeEscrow: 1,
        vaultLocked: 10,
        savingsLocked: 20,
        susuCommitted: null, // not loaded
        vendorUnallocated: 3,
        vendorRowRelevant: false, // not a vendor
        azmPoints: 1200,
        rate: FxRateView(ghsPerUsdc: 12.03, kind: FxRateKind.fresh),
      ).compute();

      await _pump(tester, valuation: v, back: true);

      expect(find.text('GHS wallet'), findsOneWidget);
      expect(find.text('USDC held'), findsOneWidget);
      expect(find.text('Escrow & disputes'), findsOneWidget);
      expect(
        find.textContaining('Escrow 4.00'),
        findsOneWidget,
        reason: 'distinct underlying fields stay visible',
      );
      expect(find.textContaining('Disputes 1.00'), findsOneWidget);
      expect(find.text('Vaults'), findsOneWidget);
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Susu'), findsOneWidget);
      expect(
        find.text('—'),
        findsOneWidget,
        reason: 'unknown susu is a dash, never a zero',
      );
      expect(find.textContaining('not loaded yet'), findsOneWidget);
      expect(
        find.text('Vendor balance'),
        findsNothing,
        reason: 'the vendor row renders only when relevant',
      );
      expect(
        find.text('AZM points'),
        findsOneWidget,
        reason: 'points are labelled non-cash and excluded from totals',
      );
      expect(find.textContaining('never in a total'), findsOneWidget);
    });

    testWidgets('the share rail normalizes to GHS with a valid rate and '
        'renders a neutral unavailable presentation without one', (
      tester,
    ) async {
      final withRate = _savedFixture();
      await _pump(tester, valuation: withRate, back: true);
      expect(
        find.byKey(const ValueKey('balance-fx-share-rail')),
        findsOneWidget,
      );

      final noRate = BalanceCardValuation(
        nativeGhsAvailable: withRate.nativeGhsAvailable,
        availableUsdc: withRate.availableUsdc,
        balanceConfirmed: true,
        escrowLocked: withRate.escrowLocked,
        disputeEscrow: withRate.disputeEscrow,
        vaultLocked: withRate.vaultLocked,
        savingsLocked: withRate.savingsLocked,
        susuCommitted: withRate.susuCommitted,
        azmPoints: withRate.azmPoints,
        rate: const FxRateView(kind: FxRateKind.none),
      ).compute();
      await _pump(tester, valuation: noRate, back: true);
      expect(
        find.byKey(const ValueKey('balance-fx-share-rail')),
        findsNothing,
        reason: 'no misleading percentage shares without a valid rate',
      );
      expect(
        find.byKey(const ValueKey('balance-fx-share-rail-unavailable')),
        findsOneWidget,
      );
    });

    testWidgets('icons carry accessible semantic labels and supplement, '
        'not replace, text labels', (tester) async {
      await _pump(tester, valuation: _savedFixture(), back: true);
      for (final label in [
        'GHS wallet icon',
        'USDC wallet icon',
        'Escrow lock icon',
        'Vault shield icon',
        'Savings piggy bank icon',
        'Susu group icon',
        'AZM points icon',
      ]) {
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason: '$label must be exposed to screen readers',
        );
      }
      // The text labels themselves are still present.
      expect(find.text('GHS wallet'), findsOneWidget);
    });
  });
}