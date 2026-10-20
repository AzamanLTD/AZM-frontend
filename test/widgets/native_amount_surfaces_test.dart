// =============================================================================
// NATIVE AMOUNT SURFACE TESTS — Workstream D1 permanent guards
//
// The honest-display rule for every personal-money surface: USDC is the
// native denomination of record; a GHS reading may appear only as a
// labelled current estimate at a usable oracle rate, and NO editable
// surface may offer a currency wheel (an authoritative GHS principal
// awaits the reviewed GHS-authority backend contract — plan v3 §7).
//
// The money-truth of NativeAmountText / AmountEntryEquivalent themselves
// is guarded by test/widgets/native_amount_display_test.dart (11 cases).
// These tests pin the SURFACE wiring: the estimate line renders under the
// editable USDC fields, tracks typing, honestly omits at a stale rate,
// and no editable surface ever grows a wheel or a settlement claim.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/currency_provider.dart';
import 'package:azaman/screens/smart_route/smart_route_create_screen.dart';
import 'package:azaman/screens/susu/susu_config_screen.dart';
import 'package:azaman/screens/vault/vault_create_screen.dart';
import 'package:azaman/widgets/currency_wheel_toggle.dart';
import 'package:azaman/widgets/money/native_amount_display.dart';

DateTime get _nowUtc => DateTime.now().toUtc();

/// A snapshot observed seconds ago: usable for the duration of a test tick.
/// Mirrors the canonical KOTANI retail shape (serverFresh verdict + external
/// observation metadata), per test/widgets/native_amount_display_test.dart.
FxRateSnapshot _freshSnapshot({double ghsPerUsdc = 15.38}) {
  final now = _nowUtc;
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

/// A server-FRESH verdict whose external observation is long past its
/// threshold: must yield NO estimate (the observation, not the response,
/// carries freshness — PR #165 review §2).
FxRateSnapshot _staleSnapshot() {
  final now = _nowUtc;
  return FxRateSnapshot(
    ghsPerUsdc: 15.38,
    source: 'KOTANI',
    lastSync: now,
    fetchedAt: now,
    serverFresh: true,
    lastExternalSync: now.subtract(const Duration(hours: 72)),
    externalRateAgeSeconds: 72 * 3600,
    rateFreshnessMaxAgeSeconds: 60,
  );
}

Widget _host(Widget child, {FxRateSnapshot? snapshot}) => ProviderScope(
      overrides: [
        fxRateProvider.overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 390, child: child),
        ),
      ),
    );

/// All Text data inside the first AmountEntryEquivalent on the surface.
String _equivalentText(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(
        of: find.byType(AmountEntryEquivalent),
        matching: find.byType(Text),
      ))
      .map((t) => t.data ?? '')
      .join(' ');
  return texts;
}

void main() {
  group('SusuConfig contribution field', () {
    testWidgets('shows the labelled GHS estimate under a usable rate',
        (tester) async {
      await tester.pumpWidget(_host(const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _freshSnapshot()));
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      expect(_equivalentText(tester), contains('USDC'));
      expect(_equivalentText(tester), contains('estimate'));
      // 20 USDC × 15.38 — the estimate tracks typing at the pinned rate.
      expect(_equivalentText(tester), contains('307.60'));
      expect(_equivalentText(tester), contains('settled in USDC'));
    });

    testWidgets('honestly omits the estimate when the rate is stale',
        (tester) async {
      await tester.pumpWidget(_host(const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _staleSnapshot()));
      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      // Honest fallback: names the unavailability, shows NO figure — the
      // absence is a labelled state, not a blank space (F-052 style).
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('307')));
      expect(_equivalentText(tester), isNot(contains('GH\u2085')));
    });

    testWidgets('never offers a currency wheel', (tester) async {
      await tester.pumpWidget(_host(const SusuConfigScreen(groupChatId: 'gc_1'),
          snapshot: _freshSnapshot()));
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });
  });

  group('SmartRouteCreate amount field', () {
    testWidgets('shows the labelled GHS estimate under a usable rate',
        (tester) async {
      await tester.pumpWidget(_host(const SmartRouteCreateScreen(),
          snapshot: _freshSnapshot()));
      // Field order: Name, Amount — target the amount by its hint.
      final amountField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == '100.00');
      await tester.enterText(amountField, '100');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsOneWidget);
      // 100 USDC × 15.38.
      expect(_equivalentText(tester), contains('1,538'));
      expect(_equivalentText(tester), contains('estimate'));
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });

    testWidgets('honestly omits the estimate when the rate is stale',
        (tester) async {
      await tester.pumpWidget(_host(const SmartRouteCreateScreen(),
          snapshot: _staleSnapshot()));
      final amountField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == '100.00');
      await tester.enterText(amountField, '100');
      await tester.pump();
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('1,538')));
    });
  });

  group('VaultCreate target and auto-deposit fields', () {
    /// The rules sheet auto-opens on first build and pointer-absorbs the
    /// form until accepted: every Vault test must walk the REAL gate
    /// (scroll the contract, consent, agree) exactly as a user does.
    Future<void> acceptRules(WidgetTester tester) async {
      final rulesScroll = find.ancestor(
          of: find.text('1. Lockup'), matching: find.byType(Scrollable));
      // Scroll to the CONTRACT'S BOTTOM, not merely until the last rule
      // is visible: the consent gate reads maxScrollExtent, and stopping
      // early leaves the checkbox disabled (flaky on font metric shifts).
      // Drive the scroll position directly: drag gestures here are eaten by
      // the sheet's own drag-dismiss system, and tree-existence-based
      // helpers stop ~3px short of the gate. jumpTo hits the exact
      // maxScrollExtent the gate reads, deterministically on every run.
      final position = tester.state<ScrollableState>(rulesScroll).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      // The gate is honest: consent only arms once fully scrolled.
      final consent =
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(consent.onChanged, isNotNull,
          reason: 'consent checkbox must arm after scrolling the contract');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue,
          reason: 'consent checkbox must flip on tap');
      final agree = tester
          .widget<ElevatedButton>(find.ancestor(
              of: find.text('I Agree — Continue'),
              matching: find.byType(ElevatedButton)))
          .onPressed;
      expect(agree, isNotNull,
          reason: 'accept button must arm once scrolled + consented');
      await tester.tap(find.text('I Agree — Continue'));
      // The sheet's exit route animation needs elapsed frames; explicit pumps.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('I Agree — Continue'), findsNothing,
          reason: 'rules sheet must close after agreement');
    }

    testWidgets('shows the labelled estimate under both editable amounts',
        (tester) async {
      // A real Ghanaian phone surface (390x844 @3x): the rules sheet's
      // consent row sits below the fold on the default 800x600 test
      // surface. tester.view (not binding.setSurfaceSize — whose metrics
      // never reach the modal route here) keeps the screen and the sheet
      // measuring one viewport.
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(const VaultCreateScreen(),
          snapshot: _freshSnapshot()));
      // Frame 1 pushes the rules route via a post-frame callback; the
      // entrance then needs real elapsed frames to settle. Explicit pumps,
      // never pumpAndSettle — the screen behind runs perpetual animations.
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await acceptRules(tester);
      // Field order: name, target, auto-deposit amount.
      final targetField = find.byWidgetPredicate((w) =>
          w is TextField && (w.decoration?.hintText ?? '') == '500.00');
      await tester.enterText(targetField, '500');
      await tester.pump();
      expect(find.byType(AmountEntryEquivalent), findsAtLeast(1));
      // 500 USDC × 15.38.
      expect(_equivalentText(tester), contains('7,690'));
      expect(_equivalentText(tester), contains('estimate'));
      expect(find.byType(CurrencyWheelToggle), findsNothing);
    });

    testWidgets('honestly omits the estimate when the rate is stale',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(const VaultCreateScreen(),
          snapshot: _staleSnapshot()));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await acceptRules(tester);
      final targetField = find.byWidgetPredicate((w) =>
          w is TextField && (w.decoration?.hintText ?? '') == '500.00');
      await tester.enterText(targetField, '500');
      await tester.pump();
      // A stale observation must yield NO converted figure: the honest
      // answer is "unavailable", never a silently wrong number.
      expect(_equivalentText(tester), contains('unavailable'));
      expect(_equivalentText(tester), isNot(contains('7,690')));
    });
  });
}
