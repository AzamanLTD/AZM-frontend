// =============================================================================
// BALANCE CARDS — post-009d audit regression suite
//
// Pins the invariants the 2026-09-28 post-009d audit flagged as untested:
//
//   1. PRIVACY (audit D-1, P1): the delta chip obeys the balance-visibility
//      mask. While the balance is hidden, a balance/rate change must NOT
//      surface a "+USDC 50.00" chip above the mask — the eye toggle exists so
//      amounts are unreadable in public, and the chip is an amount.
//   2. REDUCED MOTION (audit D-2, P2): the flip lands on the first frame when
//      the OS asks for reduced motion (brief acceptance #11).
//   3. SUSU UNKNOWN ≠ ZERO (audit D-3, P2): while the susu list has no data
//      (loading or failed), the Susu bucket renders a dash, never "0.00" —
//      "unavailable" must not read as "nothing".
//   4. SUSU SEMANTICS (F-022): only an ACTIVE member of an ACTIVE group
//      contributes to the committed total.
//   5. LAYOUT (audit D-4, P2): a huge balance under a tiny card does not
//      overflow the back-face grid (the amount scales down, Odometer-style).
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';
import 'package:azaman/widgets/odometer_number.dart';
import 'package:azaman/widgets/rate_refresh_indicator.dart';

/// A canned susu list the card's watcher will actually receive.
class _SusuListWithData extends SusuListNotifier {
  _SusuListWithData(this._data);
  final List<SusuSummary> _data;

  @override
  Future<List<SusuSummary>> build() async => _data;
}

/// A list that never resolves — models both the loading and the failed state
/// (`valueOrNull` stays null in either; the card must not guess).
class _SusuListNeverLoads extends SusuListNotifier {
  @override
  Future<List<SusuSummary>> build() => Completer<List<SusuSummary>>().future;
}

SusuSummary _susu({
  required String id,
  required SusuStatus status,
  required SusuMemberStatus myStatus,
  required double contribution,
}) {
  return SusuSummary(
    id: id,
    name: 'Susu $id',
    status: status,
    contributionUsdc: contribution,
    frequency: SusuFrequency.monthly,
    totalCycles: 4,
    myCycleSlot: 1,
    myStatus: myStatus,
    myRole: 'MEMBER',
    nextCycle: null,
  );
}

Widget _wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, navigatorChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
      ),
      child: navigatorChild ?? const SizedBox.shrink(),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

/// Pumps the front face with a container the test can mutate providers on.
Future<ProviderContainer> _pumpFrontFace(
  WidgetTester tester, {
  required double balance,
  bool visible = true,
}) async {
  final container = ProviderContainer(overrides: [
    balanceDataProvider.overrideWith(
      (ref) => BalanceData(availableBalance: balance),
    ),
    oracleRateProvider.overrideWith((ref) => 1.0),
    balanceVisibleProvider.overrideWith((ref) => visible),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _wrap(const HologramBalanceCard()),
    ),
  );
  return container;
}

/// Pumps the flippable card. The susu list is overridable; extras fetching
/// degrades silently in the test sandbox (localhost, no auth token), which is
/// the F-023 failure path behaving as designed.
Future<void> _pumpFlipCard(
  WidgetTester tester, {
  SusuListNotifier? susuNotifier,
  BalanceData balance = const BalanceData(availableBalance: 100),
  Size surface = const Size(400, 240),
  bool reduceMotion = false,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final overrides = [
    balanceDataProvider.overrideWith((ref) => balance),
    oracleRateProvider.overrideWith((ref) => 1.0),
  ];
  if (susuNotifier != null) {
    overrides.add(susuListProvider.overrideWith(() => susuNotifier));
  }
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _wrap(
        const SizedBox(
          width: 320,
          height: 180,
          child: FlippableBalanceCard(),
        ),
        reduceMotion: reduceMotion,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // CurrencyNotifier and ThemeProvider read SharedPreferences in their
    // constructors; the test binding needs the mock values installed.
    SharedPreferences.setMockInitialValues({});
  });

  group('delta chip vs. the visibility mask (audit D-1)', () {
    testWidgets(
      'a balance change surfaces a chip while the balance is visible',
      (tester) async {
        final container = await _pumpFrontFace(tester, balance: 100);
        expect(find.textContaining('+USDC'), findsNothing);

        container.read(balanceDataProvider.notifier).state =
            const BalanceData(availableBalance: 150);
        await tester.pump();

        // The positive control: the chip IS the feature when visible.
        expect(find.textContaining('+USDC'), findsOneWidget);
      },
    );

    testWidgets(
      'a balance change does NOT surface a chip while the balance is hidden',
      (tester) async {
        final container = await _pumpFrontFace(
          tester,
          balance: 100,
          visible: false,
        );
        // The mask is doing its job.
        expect(find.text('••••••'), findsOneWidget);

        container.read(balanceDataProvider.notifier).state =
            const BalanceData(availableBalance: 150);
        await tester.pump();

        // THE privacy invariant: no change magnitude above the mask.
        expect(find.textContaining('+USDC'), findsNothing);
        expect(find.text('••••••'), findsOneWidget);
      },
    );
  });

  group('EXPERIENCE PASS §1 — USDC-first hero', () {
    testWidgets('the front face shows no wallet/user-id line', (tester) async {
      await _pumpFrontFace(tester, balance: 100);
      // The old truncated fingerprint ("·· abcd") must be gone. The only
      // text children are the label, the figures and the rate row.
      expect(find.textContaining('··'), findsNothing);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('the primary figure reads USDC-first', (tester) async {
      await _pumpFrontFace(tester, balance: 123.45);
      // RICHTEXT CORRECTIONS §2A: the hero is the AMOUNT. The figure
      // renders through OdometerNumber's per-slot cells, so the amount
      // contract is pinned on the odometer's own value; the "USDC" unit
      // label is a separate, visibly smaller Text beside it.
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '123.45');
      expect(find.text('USDC'), findsOneWidget);
      // GHS remains present as the SECONDARY figure (AzMoney uses a
      // no-break space between symbol and amount).
      expect(find.text('GH₵ 123.45'), findsOneWidget);
    });

    testWidgets('the USDC unit label is substantially smaller than the '
        'amount, and the amount is not ultra-heavy', (tester) async {
      await _pumpFrontFace(tester, balance: 123.45);

      final unitStyle = tester.widget<Text>(find.text('USDC')).style!;
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      final amountStyle = odometer.style;

      // §2A: the unit label is visibly smaller than the hero amount.
      expect(unitStyle.fontSize!, lessThan(amountStyle.fontSize! * 0.6));
      // §2B: the hero stays premium medium/semi-bold — not the near-black
      // w800 it used to render at.
      expect(amountStyle.fontWeight, FontWeight.w600);
    });

    testWidgets('the live rate row and refresh affordance sit on the card',
        (tester) async {
      await _pumpFrontFace(tester, balance: 100);
      expect(find.textContaining('1 USDC = GH₵'), findsOneWidget);
      expect(find.byType(RateRefreshIndicator), findsOneWidget);

      // RICHTEXT CORRECTIONS §3: the countdown is anchored to the card's
      // RIGHT side, not trailing the conversion caption. The rate text
      // starts left; the indicator lands in the right half of the card.
      final cardRect = tester.getRect(find.byType(HologramBalanceCard));
      final rateRect = tester
          .getRect(find.textContaining('1 USDC = GH₵'));
      final indicatorRect =
          tester.getRect(find.byType(RateRefreshIndicator));
      expect(rateRect.left, lessThan(cardRect.center.dx),
          reason: 'the conversion text anchors the left of the row');
      expect(indicatorRect.center.dx, greaterThan(cardRect.center.dx),
          reason: 'the refresh/countdown anchors the right of the row');
    });

    testWidgets('the rate row survives the hidden-balance mask', (tester) async {
      // The FX rate is public market data: masking the balance must not
      // hide it.
      await _pumpFrontFace(tester, balance: 100, visible: false);
      expect(find.text('••••••'), findsOneWidget);
      expect(find.textContaining('1 USDC ='), findsOneWidget);
      expect(find.byType(RateRefreshIndicator), findsOneWidget);
    });
  });

  group('reduced motion (audit D-2)', () {
    testWidgets(
      'the flip lands on the first frame when animations are disabled',
      (tester) async {
        await _pumpFlipCard(tester, reduceMotion: true);
        expect(find.text('BREAKDOWN'), findsNothing);

        await tester.tap(find.byType(FlippableBalanceCard));
        // ONE frame only — under reduced motion the flip must already be at
        // its end state, not 450ms into a spatial transition.
        await tester.pump();

        expect(find.text('BREAKDOWN'), findsOneWidget);
      },
    );
  });

  group('susu bucket (audit D-3, F-022)', () {
    testWidgets(
      'an unloaded susu list renders a dash, never a zero',
      (tester) async {
        await _pumpFlipCard(
          tester,
          susuNotifier: _SusuListNeverLoads(),
          reduceMotion: true,
        );
        await tester.tap(find.byType(FlippableBalanceCard));
        await tester.pump();

        // Unknown must not masquerade as "you have nothing committed".
        expect(find.text('—'), findsOneWidget);
      },
    );

    testWidgets(
      'only an ACTIVE member of an ACTIVE group counts toward the total',
      (tester) async {
        await _pumpFlipCard(
          tester,
          susuNotifier: _SusuListWithData([
            _susu(
              id: 'a',
              status: SusuStatus.active,
              myStatus: SusuMemberStatus.active,
              contribution: 10.5,
            ),
            // Same ACTIVE group, but the caller's membership is not ACTIVE:
            // pending a contract means funds are not locked yet.
            _susu(
              id: 'b',
              status: SusuStatus.active,
              myStatus: SusuMemberStatus.pendingContract,
              contribution: 50,
            ),
            // An ACTIVE membership in a COMPLETED group: already paid out.
            _susu(
              id: 'c',
              status: SusuStatus.completed,
              myStatus: SusuMemberStatus.active,
              contribution: 30,
            ),
          ]),
          reduceMotion: true,
        );
        await tester.tap(find.byType(FlippableBalanceCard));
        await tester.pump();

        expect(find.text('10.50'), findsOneWidget); // the susu total
        expect(find.text('50.00'), findsNothing); // pending membership excluded
        expect(find.text('30.00'), findsNothing); // completed group excluded
      },
    );
  });

  group('back-face layout (audit D-4)', () {
    testWidgets(
      'a huge balance in a small card does not overflow a cell',
      (tester) async {
        await _pumpFlipCard(
          tester,
          balance: const BalanceData(availableBalance: 1234567.89),
          surface: const Size(320, 180),
          reduceMotion: true,
        );
        await tester.tap(find.byType(FlippableBalanceCard));
        await tester.pump();

        // The figure is present (scaled down if needed, never clipped away)…
        expect(find.text('1,234,567.89'), findsOneWidget);
        // …and no RenderFlex overflow was thrown during layout.
        expect(tester.takeException(), isNull);
      },
    );
  });
}
