// POST-MERGE CORRECTIVE PASS — canonical routing + the + trigger.
//
// * Activity Details, the trade fallback, and View Deposit dispatch
//   through the CANONICAL GoRouter locations (AzRoutes), never bare
//   MaterialPageRoutes — proven behaviorally by landing on sentinel
//   screens registered at the real registry paths.
// * The + trigger announces its state honestly (icon-only affordance:
//   "Open actions" closed, "Close actions" open) and its VISUAL state
//   rebuilds from the animation controller — mid-flight rotation ticks
//   prove the tree tracks _rot itself, not incidental parent rebuilds.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/home/activity_actions.dart';
import 'package:azaman/widgets/az_logo_mark.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';

TransactionRecord _record(
  String rawType, {
  double amountUsdc = -1,
  Map<String, dynamic> metadata = const {},
  String? providerRef,
}) {
  return TransactionRecord(
    id: 'txn-$rawType',
    rawType: rawType,
    amountUsdc: amountUsdc,
    status: 'COMPLETED',
    createdAt: DateTime(2026, 10, 1, 12),
    metadata: metadata,
    providerRef: providerRef,
  );
}

/// Sentinel screen standing in for the real destinations: what matters is
/// WHICH canonical location the router lands on, not the screen itself.
class _Sentinel extends StatelessWidget {
  const _Sentinel(this.tag);
  final String tag;

  /// Renders the tag — for these tests the route builder passes the
  /// STATE'S OWN location, so the visible text proves which canonical
  /// location the router actually landed on.
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(tag)));
}

class _DispatchHost extends StatelessWidget {
  const _DispatchHost(this.record);

  final TransactionRecord record;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => ActivityActionResolver.dispatch(context, record),
        child: const Text('dispatch'),
      ),
    ),
  );
}

Future<void> _pumpDispatchHost(
  WidgetTester tester,
  TransactionRecord record,
) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, s) => _DispatchHost(record)),
      GoRoute(
        path: AzRoutes.accountActivity,
        builder: (c, s) => _Sentinel(s.uri.toString()),
      ),
      GoRoute(
        path: '/deposit',
        name: AzRouteNames.deposit,
        builder: (c, s) => _Sentinel(s.uri.toString()),
      ),
      GoRoute(
        path: '/trade/:tradeId',
        builder: (c, s) => _Sentinel(s.uri.toString()),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
}

void main() {
  group('activity actions dispatch through the canonical router', () {
    testWidgets('Details lands on /account/activity — not a '
        'MaterialPageRoute', (tester) async {
      // An unmappable raw type resolves to the Details fallback.
      await _pumpDispatchHost(
        tester,
        _record('SYSTEM_MAINTENANCE', amountUsdc: 0),
      );

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(
        find.text(AzRoutes.accountActivity),
        findsOneWidget,
        reason:
            'the sentinel reached via the canonical location '
            'renders it — Details went through the router, not a '
            'MaterialPageRoute',
      );
    });

    testWidgets('View Deposit lands on /deposit (the fiat-default '
        'canonical route)', (tester) async {
      await _pumpDispatchHost(tester, _record('DEPOSIT_FIAT', amountUsdc: 5));

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      // AzRoutes.deposit() with no parameters — the query string stays
      // empty, so the route's own fiat-default builder behavior is
      // preserved exactly.
      expect(
        find.text(AzRoutes.deposit()),
        findsOneWidget,
        reason:
            'View Deposit landed on the canonical /deposit '
            'location with no query parameters — the fiat-default '
            'behavior',
      );
    });

    testWidgets('View Trade with a reference lands on /trade/:id via the '
        'registry', (tester) async {
      await _pumpDispatchHost(
        tester,
        _record('TRADE', metadata: {'tradeId': 'tx-9'}, providerRef: null),
      );

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(
        find.text(AzRoutes.trade('tx-9')),
        findsOneWidget,
        reason:
            'the trade route is built by AzRoutes, not '
            'interpolation',
      );
    });

    testWidgets('trade fallback without a reference lands on '
        '/account/activity, canonically', (tester) async {
      await _pumpDispatchHost(
        tester,
        _record('P2P', amountUsdc: 3, providerRef: null),
      );

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(
        find.text(AzRoutes.accountActivity),
        findsOneWidget,
        reason:
            'the no-reference trade fallback is the canonical '
            'activity screen, reached through the router',
      );
    });
  });

  group('PlusLauncherTrigger — semantics + animation-driven visuals', () {
    Future<void> pumpTrigger(
      WidgetTester tester, {
      required PlusLauncherController controller,
      bool reducedMotion = false,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(400, 900),
              ).copyWith(disableAnimations: reducedMotion),
              child: Scaffold(
                body: Center(
                  child: PlusLauncherTrigger(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final triggerFinder = find.byKey(const ValueKey('plus-launcher-trigger'));

    /// 2026-10-12: the trigger no longer rotates a plus glyph — the real
    /// AZM brand mark fills cumulatively (bottom-up: fill3 → fill2 →
    /// fill1) as the affordance becomes active. The measurable visual
    /// state is the AzLogoMark's per-segment fill.
    AzLogoMark logo(WidgetTester tester) => tester.widget(
      find.descendant(of: triggerFinder, matching: find.byType(AzLogoMark)),
    );

    /// Pumps the logo-fill (220ms) to completion plus the menu's own
    /// settlement — the menu only opens after the FINAL segment lands.
    Future<void> pumpThroughFill(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('icon-only trigger announces "Open actions" closed and '
        '"Close actions" open', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(tester, controller: controller);

      expect(
        find.bySemanticsLabel('Open actions'),
        findsOneWidget,
        reason: 'the closed state announces what the button does',
      );
      expect(find.bySemanticsLabel('Close actions'), findsNothing);

      // 2026-10-12: the tap first plays the cumulative logo fill; the
      // menu (and the honest "Close actions" label) arrive only after the
      // final segment lands.
      await tester.tap(triggerFinder);
      await pumpThroughFill(tester);

      expect(
        find.bySemanticsLabel('Close actions'),
        findsOneWidget,
        reason: 'the open state announces the current affordance',
      );
      expect(find.bySemanticsLabel('Open actions'), findsNothing);

      // And back: closing flips the label again (silently, immediately).
      await tester.tap(triggerFinder);
      await tester.pump();
      expect(find.bySemanticsLabel('Open actions'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('the cumulative logo fill tracks the transition '
        'mid-flight (normal motion) — bottom-up, lower segments stay '
        'filled', (tester) async {
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(tester, controller: controller);

      // Closed at rest: the brand mark is outline-only.
      final rest = logo(tester);
      expect(rest.fill3, 0.0);
      expect(rest.fill2, 0.0);
      expect(rest.fill1, 0.0);
      expect(controller.isOpen, isFalse);

      // Open. The tap plays the 220ms cumulative fill; the tree must
      // rebuild from the fill controller tick by tick WITHOUT any parent
      // rebuild — if the trigger relied on incidental rebuilds, the
      // mid-flight fills below would all still read 0.
      await tester.tap(triggerFinder);
      // A zero-duration pump anchors the ticker's clock.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 55));
      final m1 = logo(tester);
      // t = 0.25 → the BASE segment (fill3) is a quarter-turned in…
      expect(
        m1.fill3,
        allOf(greaterThan(0), lessThan(1)),
        reason: 'the base segment fills first',
      );
      // …while the upper segments are still untouched.
      expect(m1.fill2, 0.0, reason: 'the middle band has not started');
      expect(m1.fill1, 0.0, reason: 'the top peak has not started');
      expect(
        controller.isOpen,
        isFalse,
        reason: 'the menu opens only after the final segment lands',
      );

      await tester.pump(const Duration(milliseconds: 55));
      final m2 = logo(tester);
      // t = 0.5 → the base is fully filled and STAYS filled, the middle
      // band is in flight, the peak is still untouched.
      expect(
        m2.fill3,
        1.0,
        reason: 'the base stays filled while the next segment fills',
      );
      expect(
        m2.fill2,
        allOf(greaterThan(0), lessThan(1)),
        reason: 'the middle band fills second',
      );
      expect(m2.fill1, 0.0);

      await pumpThroughFill(tester);
      final m3 = logo(tester);
      expect(m3.fill3, 1.0);
      expect(m2.fill3, 1.0); // (unchanged guard, restated for clarity)
      expect(m3.fill2, 1.0);
      expect(m3.fill1, 1.0, reason: 'settled: the mark is fully filled');
      expect(
        controller.isOpen,
        isTrue,
        reason: 'the menu opens once the fill completes',
      );

      // Closing resets the mark predictably — never left half-filled.
      await tester.tap(triggerFinder);
      await tester.pumpAndSettle();
      final m4 = logo(tester);
      expect(m4.fill3 + m4.fill2 + m4.fill1, 0.0);
      expect(controller.isOpen, isFalse);
    });

    testWidgets('reduced motion: the visual state steps instantly between '
        'closed and open (no mid-flight animation)', (tester) async {
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(tester, controller: controller, reducedMotion: true);

      expect(logo(tester).fill1, 0.0);

      await tester.tap(triggerFinder);
      await tester.pump();
      // A step, not an animation: the mark is fully filled and the menu
      // open immediately.
      final m = logo(tester);
      expect(m.fill3, 1.0);
      expect(m.fill2, 1.0);
      expect(m.fill1, 1.0);
      expect(controller.isOpen, isTrue);

      await tester.tap(triggerFinder);
      await tester.pump();
      expect(
        logo(tester).fill3,
        0.0,
        reason: 'closing resets the mark instantly',
      );
      expect(controller.isOpen, isFalse);
    });
  });

  group('source contracts — no canonical-bypass regressions', () {
    test('the + launcher Add Cash action pushes the canonical '
        'deposit route', () {
      // (2026-10-21, Workstream G) the launcher wire set moved out of
      // main.dart into lib/widgets/home/home_plus_actions.dart — an
      // extracted, testable IA builder. The canonical-route contract is
      // unchanged; the pin now reads the extracted module AND keeps a
      // main.dart guard so the wire can never silently drift back into
      // the bootstrap file.
      final source = File(
        'lib/widgets/home/home_plus_actions.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('context.push(AzRoutes.deposit())'),
        reason: 'Add Cash goes through the route registry',
      );
      expect(
        source,
        isNot(
          contains(
            "pushWithVerticalTransition(\n                        context,\n                        const DepositScreen",
          ),
        ),
        reason: 'the old imperative deposit helper is gone',
      );
      final bootstrap = File('lib/main.dart').readAsStringSync();
      expect(
        bootstrap,
        isNot(contains('const DepositScreen')),
        reason: 'main.dart must not construct deposit screen imperatively',
      );
    });

    test('activity_actions.dart: Details and Deposit navigate through '
        'AzRoutes; the migrated screens are no longer constructed here', () {
      final source = File(
        'lib/widgets/home/activity_actions.dart',
      ).readAsStringSync();
      expect(source, contains('AzRoutes.accountActivity'));
      expect(source, contains('AzRoutes.deposit()'));
      expect(
        source,
        isNot(contains('const AccountActivityScreen(')),
        reason:
            'the details screen is reached by location, not by '
            'constructing it over the router',
      );
      expect(
        source,
        isNot(contains('const DepositScreen(')),
        reason: 'the deposit screen is reached by location too',
      );
      // WORKSTREAMS B + C (integrated) — Send and Withdraw are both
      // canonical rise locations now (/send, /withdraw): the activity
      // row routes by location for both, never by constructing either
      // screen over the router.
      expect(source, contains('AzRoutes.send('));
      expect(source, contains('AzRoutes.withdraw()'));
      expect(
        source,
        isNot(contains('SendMoneyScreen')),
        reason:
            'the send surface is reached through AzRoutes.send(), '
            'never constructed imperatively',
      );
      expect(
        source,
        isNot(contains('WithdrawalScreen')),
        reason:
            'the withdrawal surface is reached through AzRoutes.withdraw(), '
            'never constructed imperatively',
      );
    });

    test('the + trigger rebuilds from the animation controller and '
        'announces both states', () {
      final source = File(
        'lib/widgets/home/plus_action_launcher.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('AnimatedBuilder'),
        reason: 'the trigger listens to the rotation controller',
      );
      expect(source, contains("'Open actions'"));
      expect(source, contains("'Close actions'"));
    });
  });
}
