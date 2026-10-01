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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/transaction_history_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/widgets/home/activity_actions.dart';
import 'package:azaman/widgets/home/plus_action_launcher.dart';

TransactionRecord _record(String rawType,
    {double amountUsdc = -1,
    Map<String, dynamic> metadata = const {},
    String? providerRef}) {
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
    WidgetTester tester, TransactionRecord record) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
          path: '/',
          builder: (c, s) => _DispatchHost(record)),
      GoRoute(
          path: AzRoutes.accountActivity,
          builder: (c, s) => _Sentinel(s.uri.toString())),
      GoRoute(
          path: '/deposit',
          name: AzRouteNames.deposit,
          builder: (c, s) => _Sentinel(s.uri.toString())),
      GoRoute(
          path: '/trade/:tradeId',
          builder: (c, s) => _Sentinel(s.uri.toString())),
    ],
  );
  await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)));
}

void main() {
  group('activity actions dispatch through the canonical router', () {
    testWidgets('Details lands on /account/activity — not a '
        'MaterialPageRoute', (tester) async {
      // An unmappable raw type resolves to the Details fallback.
      await _pumpDispatchHost(
          tester, _record('SYSTEM_MAINTENANCE', amountUsdc: 0));

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(find.text(AzRoutes.accountActivity), findsOneWidget,
          reason: 'the sentinel reached via the canonical location '
              'renders it — Details went through the router, not a '
              'MaterialPageRoute');
    });

    testWidgets('View Deposit lands on /deposit (the fiat-default '
        'canonical route)', (tester) async {
      await _pumpDispatchHost(
          tester, _record('DEPOSIT_FIAT', amountUsdc: 5));

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      // AzRoutes.deposit() with no parameters — the query string stays
      // empty, so the route's own fiat-default builder behavior is
      // preserved exactly.
      expect(find.text(AzRoutes.deposit()), findsOneWidget,
          reason: 'View Deposit landed on the canonical /deposit '
              'location with no query parameters — the fiat-default '
              'behavior');
    });

    testWidgets('View Trade with a reference lands on /trade/:id via the '
        'registry', (tester) async {
      await _pumpDispatchHost(tester,
          _record('TRADE', metadata: {'tradeId': 'tx-9'}, providerRef: null));

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(find.text(AzRoutes.trade('tx-9')), findsOneWidget,
          reason: 'the trade route is built by AzRoutes, not '
              'interpolation');
    });

    testWidgets('trade fallback without a reference lands on '
        '/account/activity, canonically', (tester) async {
      await _pumpDispatchHost(
          tester, _record('P2P', amountUsdc: 3, providerRef: null));

      await tester.tap(find.text('dispatch'));
      await tester.pumpAndSettle();

      expect(find.text(AzRoutes.accountActivity), findsOneWidget,
          reason: 'the no-reference trade fallback is the canonical '
              'activity screen, reached through the router');
    });
  });

  group('PlusLauncherTrigger — semantics + animation-driven visuals', () {
    Future<void> pumpTrigger(WidgetTester tester,
        {required PlusLauncherController controller,
        bool reducedMotion = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeProvider.getThemeData(AzamanTheme.light),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(400, 900))
                  .copyWith(disableAnimations: reducedMotion),
              child: Scaffold(
                body: Center(child: PlusLauncherTrigger(controller: controller)),
              ),
            ),
          ),
        ),
      );
    }

    final triggerFinder =
        find.byKey(const ValueKey('plus-launcher-trigger'));

    /// The rotation angle of the trigger's Transform, read from its
    /// matrix (Transform.rotate stores a Matrix4, not a `angle` field).
    /// Pure rotation about z: storage[0]=cos, storage[1]=sin.
    double angle(WidgetTester tester) {
      final m = tester
          .widget<Transform>(find
              .descendant(of: triggerFinder, matching: find.byType(Transform))
              .first)
          .transform
          .storage;
      return math.atan2(m[1], m[0]).abs();
    }

    testWidgets('icon-only trigger announces "Open actions" closed and '
        '"Close actions" open', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(tester, controller: controller);

      expect(find.bySemanticsLabel('Open actions'), findsOneWidget,
          reason: 'the closed state announces what the button does');
      expect(find.bySemanticsLabel('Close actions'), findsNothing);

      await tester.tap(triggerFinder);
      await tester.pump();

      expect(find.bySemanticsLabel('Close actions'), findsOneWidget,
          reason: 'the open state announces the current affordance');
      expect(find.bySemanticsLabel('Open actions'), findsNothing);

      // And back: closing flips the label again.
      await tester.tap(triggerFinder);
      await tester.pump();
      expect(find.bySemanticsLabel('Open actions'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('the rotation rebuilds from the animation controller — '
        'the visual state tracks the transition mid-flight (normal '
        'motion)', (tester) async {
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(tester, controller: controller);

      // Closed at rest: no rotation at all.
      expect(angle(tester), 0.0);

      // Open. The controller starts the animation; the angle must track
      // it tick by tick WITHOUT any parent rebuild happening — if the
      // trigger relied on incidental rebuilds, the mid-flight angles
      // below would all still read 0.
      await tester.tap(triggerFinder);
      // A zero-duration pump anchors the ticker's clock (its first tick
      // reports elapsed 0) — after this, advancing the clock moves the
      // animation value.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final a1 = angle(tester);
      expect(a1, allOf(greaterThan(0), lessThan(0.125 * 2 * math.pi)),
          reason: 'mid-transition: partially rotated');

      await tester.pump(const Duration(milliseconds: 60));
      final a2 = angle(tester);
      expect(a2, greaterThan(a1),
          reason: 'the tree keeps rebuilding from _rot as it advances');

      await tester.pumpAndSettle();
      expect(angle(tester), moreOrLessEquals(0.125 * 2 * math.pi),
          reason: 'settled at the open-state quarter-eighth turn');

      // Closing reverses through the same controller-driven path.
      await tester.tap(triggerFinder);
      await tester.pumpAndSettle();
      expect(angle(tester), 0.0);
    });

    testWidgets('reduced motion: the visual state steps instantly between '
        'closed and open (no mid-flight animation)', (tester) async {
      final controller = PlusLauncherController();
      addTearDown(controller.dispose);

      await pumpTrigger(
          tester, controller: controller, reducedMotion: true);

      expect(angle(tester), 0.0);

      await tester.tap(triggerFinder);
      await tester.pump();
      // A step, not an animation: the full open-state angle immediately.
      expect(angle(tester), moreOrLessEquals(0.125 * 2 * math.pi));

      await tester.tap(triggerFinder);
      await tester.pump();
      expect(angle(tester), 0.0);
    });
  });

  group('source contracts — no canonical-bypass regressions', () {
    test('main.dart: the + launcher Add Cash action pushes the canonical '
        'deposit route', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('context.push(AzRoutes.deposit())'),
          reason: 'Add Cash goes through the route registry');
      expect(
          source,
          isNot(contains(
              "pushWithVerticalTransition(\n                        context,\n                        const DepositScreen")),
          reason: 'the old imperative deposit helper is gone');
    });

    test('activity_actions.dart: Details and Deposit navigate through '
        'AzRoutes; the migrated screens are no longer constructed here',
        () {
      final source =
          File('lib/widgets/home/activity_actions.dart').readAsStringSync();
      expect(source, contains('AzRoutes.accountActivity'));
      expect(source, contains('AzRoutes.deposit()'));
      expect(source, isNot(contains('const AccountActivityScreen(')),
          reason: 'the details screen is reached by location, not by '
              'constructing it over the router');
      expect(source, isNot(contains('const DepositScreen(')),
          reason: 'the deposit screen is reached by location too');
      // SendMoney and Withdrawal still genuinely have no canonical
      // routes — their imperative navigation is the sanctioned exception.
      expect(source, contains('SendMoneyScreen'));
      expect(source, contains('WithdrawalScreen'));
    });

    test('the + trigger rebuilds from the animation controller and '
        'announces both states', () {
      final source = File('lib/widgets/home/plus_action_launcher.dart')
          .readAsStringSync();
      expect(source, contains('AnimatedBuilder'),
          reason: 'the trigger listens to the rotation controller');
      expect(source, contains("'Open actions'"));
      expect(source, contains("'Close actions'"));
    });
  });
}
