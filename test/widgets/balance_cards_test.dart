// =============================================================================
// BALANCE CARDS — post-009d audit regression suite
//
// Pins the invariants the 2026-09-28 post-009d audit flagged as untested:
//
//   1. PRIVACY (WALLET POUCH, 2026-10-16): the balance-visibility eye is
//      GONE — the card face is always fully rendered. The privacy state is
//      the Home wallet pouch (the tucked deck), covered by the deck suite.
//      Here we pin the removal: no eye control, no mask dots, and the real
//      figure always present when the card is on screen.
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
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;
// RenderRepaintBoundary comes from flutter/rendering (via material).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/susu_model.dart';
import 'package:azaman/providers/hologram_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/susu_provider.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';
import 'package:azaman/widgets/flippable_balance_card.dart';
import 'package:azaman/widgets/hologram_balance_card.dart';
import 'package:azaman/widgets/holographic_surface.dart';
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

/// Seeds the display-currency preference BEFORE any provider in this
/// test reads SharedPreferences (CurrencyNotifier loads at construction).
Future<void> _seedCurrency(String? value) async {
  SharedPreferences.setMockInitialValues(
      value == null ? {} : {'display_currency': value});
}

/// Pumps the front face with a container the test can mutate providers on.
Future<ProviderContainer> _pumpFrontFace(
  WidgetTester tester, {
  required double balance,
  double rate = 1.0,
  bool reduceMotion = false,
}) async {
  final container = ProviderContainer(overrides: [
    balanceDataProvider.overrideWith(
      (ref) => BalanceData(availableBalance: balance),
    ),
    balanceReadinessProvider.overrideWith(
        (ref) => BalanceReadiness.loaded),
    oracleRateProvider.overrideWith((ref) => rate),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _wrap(
        const HologramBalanceCard(),
        reduceMotion: reduceMotion,
      ),
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
    balanceReadinessProvider.overrideWith(
        (ref) => BalanceReadiness.loaded),
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



  group('GHANA-FIRST (2026-10-20) — GHS is the default primary', () {
    testWidgets(
      'PR #165 §5 + WORKSTREAM B — an unresolved rate keeps the USDC '
      'ledger balance visible and the cedi equivalent slot WAITING '
      '(three-dot indicator, never "GH₵ 0.00" and never an unavailable '
      'caption)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpFrontFace(tester, balance: 50.0, rate: 0);

    // The REAL ledger balance stays primary and visible. The hero
    // renders the balance as per-digit odometer cells, so the assertion
    // targets the card's own semantics label — the full formatted amount.
    expect(find.bySemanticsLabel(RegExp('USDC.50.00\\savailable')),
        findsOneWidget,
        reason: 'the funded USDC ledger balance must stay visible');

    // WORKSTREAM B: the equivalent slot waits with the three-dot
    // indicator, named for screen readers as a loading state.
    expect(find.byKey(const ValueKey('home-balance-fx-dots')),
        findsOneWidget,
        reason: 'the unresolved cedi equivalent shows the waiting dots');
    expect(find.text('GH₵ equivalent unavailable'), findsNothing,
        reason: 'WORKSTREAM B removed the unavailable caption');
    expect(find.bySemanticsLabel('Exchange rate loading'), findsOneWidget,
        reason: 'the waiting slot announces what is loading');
    expect(find.text('GH\u20B5\u00A00.00'), findsNothing,
        reason: 'a fabricated live-looking zero equivalent must never render');
    expect(find.byKey(const ValueKey('hologram-rate-unavailable')),
        findsOneWidget,
        reason: 'the rate row still says FX unavailable, never '
            '1 USDC = GH₵ 0.00');
    handle.dispose();
  });

    testWidgets('the un-seeded preference renders GHS-primary with the '
        'USDC ledger equivalent as the secondary figure', (tester) async {
      await _seedCurrency(null);
      await _pumpFrontFace(tester, balance: 123.45);

      // GHS-primary: the hero figure is the GHS equivalent of the ledger
      // balance (123.45 * 1.0) and the secondary line is the USDC ledger
      // truth ('USDC\u00A0123.45'), so the user always knows what they hold.
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '123.45',
          reason: 'the hero shows the GHS-equivalent figure');
      expect(find.text('USDC\u00A0123.45'), findsOneWidget,
          reason: 'the secondary line is the USDC ledger equivalent');
      // WORKSTREAM B: the unit mark is now a quiet label, not a wheel chip.
      expect(find.byKey(const ValueKey('home-balance-primary-unit')),
          findsOneWidget,
          reason: 'the figure keeps its visible unit mark');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('home-balance-primary-unit')))
              .data,
          'GH₵',
          reason: 'the primary unit is the cedi under the global GHS '
              'preference');
    });

    testWidgets('a distinct rate proves the figure is CONVERTED, not '
        'relabeled — and the global preference converts the value back',
        (tester) async {
      await _seedCurrency(null);
      await _pumpFrontFace(tester, balance: 123.45, rate: 15.38);

      // 123.45 USDC * 15.38 = 1898.66 GHS (half-up at 2 decimals).
      final odometer =
          tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '1,898.66');
      expect(find.text('USDC\u00A0123.45'), findsOneWidget);

      // Switching the GLOBAL preference (not a card-local wheel) converts
      // the SAME balance back through the SAME rate — a numeric
      // conversion, never a label swap.
      await _seedCurrency('usdc');
      await _pumpFrontFace(tester, balance: 123.45, rate: 15.38);
      await tester.pump(const Duration(milliseconds: 100));

      final after = tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(after.value, '123.45',
          reason: 'the figure converts back to the ledger unit');
      expect(find.text('GH\u20B5\u00A01,898.66'), findsOneWidget,
          reason: 'GHS becomes the secondary equivalent');
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('home-balance-primary-unit')))
              .data,
          'USDC',
          reason: 'the unit mark follows the global preference');
    });

    testWidgets('WORKSTREAM B — the card carries no display-currency '
        'wheel; it only READS the global preference', (tester) async {
      await _seedCurrency('usdc');
      await _pumpFrontFace(tester, balance: 100);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('home-balance-currency-wheel')),
          findsNothing,
          reason: 'the Home card no longer owns a currency switch');
      expect(find.byType(CurrencyWheelToggle), findsNothing,
          reason: 'no wheel of any identity rides the card');

      final odometer = tester.widget<OdometerNumber>(find.byType(OdometerNumber));
      expect(odometer.value, '100.00',
          reason: 'the global USDC preference still drives the hero');
      expect(find.text('GH\u20B5\u00A0100.00'), findsOneWidget,
          reason: 'the cedi equivalent stays secondary');
    });

    testWidgets('an FX-rate change re-baselines the delta chip silently — '
        'a rate change never masquerades as balance movement',
        (tester) async {
      await _seedCurrency(null);
      await _pumpFrontFace(tester, balance: 100, rate: 15);
      await tester.pump(const Duration(milliseconds: 400));

      // A real balance move shows the chip, denominated in the PRIMARY unit.
      // The LIVE container is the one powering the current tree.
      final container = await _pumpFrontFace(tester, balance: 120, rate: 15);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('+GH\u20B5\u00A0300.00'), findsOneWidget,
          reason: 'a genuine +20 USDC move surfaces as +300 GHS at rate 15');

      // A RATE change changes the figure's MEANING, not the balance: the
      // chip must vanish (re-baselined) instead of showing a fake move.
      container.read(oracleRateProvider.notifier).state = 16.0;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('+GH\u20B5\u00A0300.00'), findsNothing,
          reason: 'a rate change is not balance movement');
      // …and the figure truthfully shows the new conversion.
      expect(
          tester.widget<OdometerNumber>(find.byType(OdometerNumber)).value,
          '1,920.00',
          reason: '120 USDC * 16.00 = 1,920.00 GHS');
    });
  });

  group('WORKSTREAM B — three-dot waiting indicator (unresolved FX)', () {
    testWidgets(
        'a valid rate ARRIVING replaces the dots with the true equivalent '
        'without shifting the card layout', (tester) async {
      final container = await _pumpFrontFace(tester, balance: 123.45, rate: 0);
      final before = tester.getRect(find.byType(HologramBalanceCard));
      expect(find.byKey(const ValueKey('home-balance-fx-dots')),
          findsOneWidget);

      container.read(oracleRateProvider.notifier).state = 15.38;
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('home-balance-fx-dots')), findsNothing,
          reason: 'the waiting dots leave once a rate lands');
      // The converted figure IS the hero under the default GHS preference:
      // 123.45 USDC * 15.38 = 1,898.66 GHS.
      expect(tester.widget<OdometerNumber>(find.byType(OdometerNumber)).value,
          '1,898.66',
          reason: 'the cedi equivalent renders with the true conversion');
      expect(find.text('USDC\u00A0123.45'), findsOneWidget,
          reason: 'the USDC ledger truth stays secondary');
      final after = tester.getRect(find.byType(HologramBalanceCard));
      expect(after.height, before.height,
          reason: 'the card height never accommodates the indicator');
    });

    testWidgets(
        'a genuine loaded ZERO balance stays a zero — the dots are for '
        'unresolved VALUES, not small numbers', (tester) async {
      await _pumpFrontFace(tester, balance: 0, rate: 15);
      expect(tester.widget<OdometerNumber>(find.byType(OdometerNumber)).value,
          '0.00',
          reason: 'a real loaded zero is a truthful figure');
      expect(find.byKey(const ValueKey('home-balance-fx-dots')), findsNothing,
          reason: 'resolved FX never shows waiting dots');
      expect(find.text('USDC\u00A00.00'), findsOneWidget,
          reason: 'zero converts honestly too');
    });

    testWidgets(
        'the dots RISE AND FALL — staggered vertical motion runs while '
        'motion is allowed', (tester) async {
      await _pumpFrontFace(tester, balance: 50, rate: 0);
      final dots = find.byKey(const ValueKey('home-balance-fx-dots'));

      double minY = 0;
      // One full cycle plus a frame, stepped like a ticker.
      for (var t = 0; t <= 1100; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
        for (final t2
            in tester.widgetList<Transform>(find.descendant(of: dots, matching: find.byType(Transform)))) {
          final dy = t2.transform.getTranslation().y;
          if (dy < minY) minY = dy;
        }
      }
      expect(minY, lessThan(-1.0),
          reason: 'at least one dot rose visibly during the cycle '
              '(rise = 3px)');
    });

    testWidgets(
        'reduced motion: the dots sit still (no ticking) but stay '
        'announced and occupy the slot', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpFrontFace(tester, balance: 50, rate: 0, reduceMotion: true);
      final dots = find.byKey(const ValueKey('home-balance-fx-dots'));
      expect(dots, findsOneWidget);
      expect(find.bySemanticsLabel('Exchange rate loading'), findsOneWidget);

      double moved = 0;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        for (final t2 in tester.widgetList<Transform>(
            find.descendant(of: dots, matching: find.byType(Transform)))) {
          moved = math.max(moved, t2.transform.getTranslation().y.abs());
        }
      }
      expect(moved, 0.0,
          reason: 'under reduced motion the indicator never moves');
      handle.dispose();
    });

    testWidgets(
        'the dots stay inside the card at 320dp and dispose cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 260));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpFrontFace(tester, balance: 50, rate: 0);

      final card = tester.getRect(find.byType(HologramBalanceCard));
      final dots = tester.getRect(find.byKey(const ValueKey('home-balance-fx-dots')));
      expect(dots.left, greaterThanOrEqualTo(card.left));
      expect(dots.right, lessThanOrEqualTo(card.right));
      expect(tester.takeException(), isNull,
          reason: 'no overflow at 320dp with the waiting dots');

      // Disposal: the ticker dies with the card — the framework's
      // pending-timer invariant proves it at test end.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
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
      await _seedCurrency('usdc');
      await _pumpFrontFace(tester, balance: 123.45);
      // The preference load is async: one bounded pump lets the seeded
      // 'usdc' land before the contract is asserted.
      await tester.pump(const Duration(milliseconds: 100));
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
      await _seedCurrency('usdc');
      await _pumpFrontFace(tester, balance: 123.45);
      // The preference load is async: one bounded pump lets the seeded
      // 'usdc' land before the contract is asserted.
      await tester.pump(const Duration(milliseconds: 100));

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

    testWidgets('the surface is neutral graphite in dark mode — the '
        'iridescence tint is NOT the accent (RICHTEXT CORRECTIONS §2C)',
        (tester) async {
      await _pumpFrontFace(tester, balance: 100);
      // The theme load is async (SharedPreferences mock: no saved
      // preference → the default DARK theme). Two fixed pumps — the first
      // flushes the load microtask, the second builds with the dark
      // palette. NOT pumpAndSettle: RateRefreshIndicator counts down on a
      // repeating timer, so settling never terminates.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final surface = tester.widget<HolographicSurface>(
          find.byType(HolographicSurface));
      final colors = ThemeProvider.getColors(AzamanTheme.dark);
      // The material base is the palette's neutral near-black graphite.
      expect(surface.base, colors.card);
      // The tint drives the broad iridescent wash: accent gold there
      // produced the muddy olive/khaki card the screenshots flagged.
      expect(surface.tint, colors.textSecondary);
      expect(surface.tint, isNot(colors.accent));
    });

  });



  group('WALLET POUCH — the eye is gone, privacy is the deck', () {
    testWidgets(
      'no eye control renders on the card — and no mask dots either',
      (tester) async {
        await _pumpFrontFace(tester, balance: 123.45);
        // The eye control and the masked figure are both gone from the
        // card; the tucked pouch deck owns privacy now.
        expect(find.bySemanticsLabel('Toggle balance visibility'),
            findsNothing,
            reason: 'the eye semantics control must not exist');
        expect(find.text('••••••••'), findsNothing,
            reason: 'the mask dots belong to the removed hide state');
      },
    );

    testWidgets(
      'the real figure is always present when the card is on screen',
      (tester) async {
        await _pumpFrontFace(tester, balance: 123.45);
        expect(find.textContaining('123'), findsOneWidget,
            reason: 'the card face renders the real amount; privacy is '
                'physical (the pouch), not a mask');
        expect(find.byType(OdometerNumber), findsOneWidget);
      },
    );
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

  group('WORKSTREAM B — captures (light/dark × 320/360/390 × FX states)',
      () {
    const rootKey = Key('balance-card-capture-root');
    bool fontsLoaded = false;

    Future<void> loadFonts() async {
      if (fontsLoaded) return;
      final inter =
          await File('assets/fonts/Inter-Variable.ttf').readAsBytes();
      final loader = FontLoader('Inter')
        ..addFont(Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(inter).buffer)));
      await loader.load();
      fontsLoaded = true;
    }

    Future<void> capture(WidgetTester tester, String name) async {
      var ok = false;
      await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        Directory('.screenshots/workstream_b_balance_card')
            .createSync(recursive: true);
        File('.screenshots/workstream_b_balance_card/$name.png')
            .writeAsBytesSync(data.buffer.asUint8List());
        ok = true;
      });
      expect(ok, isTrue, reason: 'capture $name wrote a PNG');
    }

    testWidgets('front face, both FX states, both themes, three widths',
        (tester) async {
      await tester.runAsync(loadFonts);
      for (final themeName in ['light', 'dark']) {
        for (final width in [320.0, 360.0, 390.0]) {
          for (final state in ['waiting', 'resolved']) {
            await tester.binding.setSurfaceSize(Size(width, 260));
            // The theme preference is read by the ThemeProvider at load;
            // the currency preference stays un-seeded (GHS-primary default).
            SharedPreferences.setMockInitialValues(themeName == 'dark'
                ? {'azaman_theme': 1}
                : {'azaman_theme': 0});
            final rate = state == 'waiting' ? 0.0 : 15.38;
            final container = ProviderContainer(overrides: [
              balanceDataProvider.overrideWith(
                (ref) => const BalanceData(availableBalance: 123.45),
              ),
              balanceReadinessProvider.overrideWith(
                  (ref) => BalanceReadiness.loaded),
              oracleRateProvider.overrideWith((ref) => rate),
            ]);
            addTearDown(container.dispose);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  home: Scaffold(
                    backgroundColor: themeName == 'dark'
                        ? const Color(0xFF0A0C12)
                        : const Color(0xFFF2F3F5),
                    body: Center(
                      child: SizedBox(
                        width: width - 24,
                        child: const RepaintBoundary(
                          key: rootKey,
                          child: HologramBalanceCard(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            // Settle the entrance, delta and FX-dots animations with
            // bounded frame steps (pumpAndSettle hangs on the refresh
            // countdown timer).
            for (var i = 0; i < 14; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (state == 'waiting') {
              expect(find.byKey(const ValueKey('home-balance-fx-dots')),
                  findsOneWidget);
            } else {
              expect(find.byKey(const ValueKey('home-balance-fx-dots')),
                  findsNothing);
            }
            await capture(
                tester, 'balance_${state}_${themeName}_${width.toInt()}');
            await tester.pumpWidget(const SizedBox());
          }
        }
      }
      await tester.binding.setSurfaceSize(null);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // WORKSTREAM B — explicit balance readiness states
  // ═════════════════════════════════════════════════════════════════════════
  group('Workstream B — balance readiness states', () {
    /// The primary amount slot's waiting indicator (Workstream B).
    Finder heroAmount() =>
        find.byKey(const ValueKey('home-balance-amount-dots'));

    testWidgets('initial state: waiting dots, never a fabricated 0.00',
        (tester) async {
      final container = ProviderContainer(overrides: [
        // Pin the rate: the real OracleRatesClient starts polling timers
        // that leak past this test's disposal window.
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      // The primary amount slot holds the waiting indicator…
      expect(heroAmount(), findsOneWidget);

      // …and never a formatted zero masquerading as a confirmed balance.
      final zeroTexts = find
          .byWidgetPredicate((w) =>
              w is Text &&
              (w.data ?? '').contains('0.00'))
          .evaluate();
      expect(zeroTexts, isEmpty,
          reason: 'unresolved must not print USDC 0.00');

      // Semantics tell the truth: loading, not zero.
      expect(
        find.bySemanticsLabel(RegExp('balance loading|Balance loading')),
        findsOneWidget,
      );
    });

    testWidgets('hydration: balance + readiness arriving shows the figure',
        (tester) async {
      final container = ProviderContainer(overrides: [
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(heroAmount(), findsOneWidget);

      // The canonical refresh lands: balance AND readiness together.
      container.read(balanceDataProvider.notifier).state =
          const BalanceData(availableBalance: 87.5);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.loaded;
      await tester.pump(const Duration(milliseconds: 120));

      expect(heroAmount(), findsNothing);
      // The odometer renders rolling digits, so the confirmed value is
      // asserted through its semantics label.
      expect(
        find.bySemanticsLabel(RegExp(r'87\.5.*available')),
        findsOneWidget,
        reason: 'loaded positive balance renders its figure',
      );
    });

    testWidgets('genuine loaded zero stays a real 0.00', (tester) async {
      final container = ProviderContainer(overrides: [
        balanceReadinessProvider.overrideWith(
            (ref) => BalanceReadiness.loaded),
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(heroAmount(), findsNothing,
          reason: 'a loaded zero is a VALUE, not an unresolved slot');
      expect(
        find.bySemanticsLabel(RegExp(r'0\.00 available')),
        findsOneWidget,
        reason: 'genuine zero balance displays 0.00',
      );
    });

    testWidgets('failed fetch with no usable value: dots, never fake zero',
        (tester) async {
      final container = ProviderContainer(overrides: [
        balanceReadinessProvider.overrideWith(
            (ref) => BalanceReadiness.failed),
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(heroAmount(), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('balance unavailable|Balance unavailable')),
        findsOneWidget,
      );
      final zeroTexts = find
          .byWidgetPredicate((w) =>
              w is Text && (w.data ?? '').contains('0.00'))
          .evaluate();
      expect(zeroTexts, isEmpty);
    });

    testWidgets('loaded balance with FX unresolved: USDC value + FX dots',
        (tester) async {
      final container = ProviderContainer(overrides: [
        balanceDataProvider.overrideWith(
            (ref) => const BalanceData(availableBalance: 42.25)),
        balanceReadinessProvider.overrideWith(
            (ref) => BalanceReadiness.loaded),
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      // The native USDC balance is confirmed — it renders as a value…
      expect(heroAmount(), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'42\.25 available')),
          findsOneWidget);
      // …while the optional cedi equivalent waits: dots in the FX slot.
      expect(find.byKey(const ValueKey('home-balance-fx-dots')),
          findsOneWidget);
    });

    testWidgets('FX recovery: dots resolve into a cedi equivalent',
        (tester) async {
      final container = ProviderContainer(overrides: [
        balanceDataProvider.overrideWith(
            (ref) => const BalanceData(availableBalance: 10)),
        balanceReadinessProvider.overrideWith(
            (ref) => BalanceReadiness.loaded),
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const ValueKey('home-balance-fx-dots')),
          findsOneWidget);

      // The rate lands.
      container.read(oracleRateProvider.notifier).state = 15.5;
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const ValueKey('home-balance-fx-dots')),
          findsNothing);
      // GHS-first default: the recovered rate makes the cedi figure the
      // primary (odometer → semantics), with the USDC pair visible as text.
      expect(find.bySemanticsLabel(RegExp(r'155.*available')),
          findsOneWidget,
          reason: '10 USDC at 15.5 = GH\u20B5 155.00 primary');
      expect(find.textContaining('10'), findsWidgets,
          reason: 'the native USDC pair stays visible as the secondary');
    });

    testWidgets('failed refresh AFTER a loaded balance keeps the figure',
        (tester) async {
      // The provider's own contract: markFailed() must not demote a
      // loaded readiness. Drive refreshCanonicalBalance in the sandbox —
      // the secure-storage read throws (no plugin), landing in the
      // catch-all, which is exactly the failure path under test.
      final container = ProviderContainer(overrides: [
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);

      container.read(balanceDataProvider.notifier).state =
          const BalanceData(availableBalance: 64.0);
      container.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.loaded;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.bySemanticsLabel(RegExp(r'64\.0.*available')),
          findsOneWidget);

      // A refresh attempt fails (no secure storage in the test sandbox).
      await tester.runAsync(
          () => refreshCanonicalBalance(container));
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        container.read(balanceReadinessProvider),
        BalanceReadiness.loaded,
        reason: 'a failed refresh never demotes a usable loaded value',
      );
      expect(find.bySemanticsLabel(RegExp(r'64\.0.*available')),
          findsOneWidget,
          reason: 'the last confirmed figure stays on the card');
    });

    testWidgets('failed refresh BEFORE any load marks readiness failed',
        (tester) async {
      final container = ProviderContainer(overrides: [
        oracleRateProvider.overrideWith((ref) => 0.0),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrap(const HologramBalanceCard()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      await tester.runAsync(
          () => refreshCanonicalBalance(container));
      await tester.pump(const Duration(milliseconds: 120));

      expect(container.read(balanceReadinessProvider),
          BalanceReadiness.failed);
      expect(heroAmount(), findsOneWidget);
    });
  });
}
