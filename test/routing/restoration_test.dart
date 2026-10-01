// =============================================================================
// AZM — NEW-A STATE RESTORATION TESTS
//
// Proves the restoration contract the NEW-A audit requires — not that a
// field exists, but that restoration actually happens after app/widget
// tree reconstruction:
//
//   1. The real AccountActivityScreen's scroll offset survives a full
//      app restart. `tester.restartAndRestore()` serializes the
//      restoration data, tears down the entire widget tree (destroying
//      every State, controller and entry list in memory) and rebuilds it
//      from the serialized data — the same data flow as process death.
//
//   2. The same proof through the REAL router: GoRouter restoration
//      scope ('azm-router'), the route's stable page restoration
//      identity (its route name, applied by the rise transition
//      family), ModalRoute's route-level RestorationScope, and the
//      screen's restored scroll offset.
//
//   3. A second restart restores the offset written during the
//      reconstructed session — restoration data stays live, not stale.
//
// Data comes from the demo interceptor (30 seeded security events), so
// the list is a genuine long-scroll surface.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/config.dart';
import 'package:azaman/router/app_router.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/screens/account_activity_screen.dart';

void main() {
  setUpAll(() {
    // Demo mode routes /users/me/security-logs to DemoInterceptor's
    // seeded 30-entry security log — no network in tests.
    AppConfig.enableDemoMode();
  });

  Finder restoreeListFinder() => find.byWidgetPredicate(
        (w) => w is ListView && w.controller != null,
      );

  double listOffset(WidgetTester tester) =>
      tester.widget<ListView>(restoreeListFinder()).controller!.position.pixels;

  Future<double> scrollDownList(
    WidgetTester tester, {
    int drags = 2,
    double amount = -320,
  }) async {
    for (var i = 0; i < drags; i++) {
      await tester.drag(restoreeListFinder(), Offset(0, amount));
      await tester.pumpAndSettle();
    }
    return listOffset(tester);
  }

  testWidgets(
    'AccountActivityScreen scroll offset survives app restart '
    '(serialized restoration data, all in-memory state destroyed)',
    (tester) async {
      Widget harness() => const ProviderScope(
            child: MaterialApp(
              restorationScopeId: 'root',
              home: AccountActivityScreen(),
            ),
          );

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(listOffset(tester), 0);

      final recorded = await scrollDownList(tester);
      expect(recorded, greaterThan(0));

      // Framework-blessed app-restart simulation: serializes restoration
      // data, tears down the ENTIRE widget tree (every State, the scroll
      // controller, the loaded entries are destroyed), then rebuilds from
      // the serialized data. The offset can only come back from the
      // restoration system — no custom cache exists.
      await tester.restartAndRestore();
      await tester.pumpAndSettle();

      expect(
        listOffset(tester),
        moreOrLessEquals(recorded, epsilon: 0.5),
        reason: 'scroll offset must be restored from serialized '
            'restoration data after the app restart, not from any '
            'surviving in-memory state',
      );
    },
  );

  testWidgets(
    'router harness: route restoration identity + scroll offset restore '
    'through the real GoRouter page stack',
    (tester) async {
      Widget harness() => ProviderScope(
            child: MaterialApp.router(
              restorationScopeId: 'root',
              routerConfig: appRouter,
            ),
          );

      // Navigate before the first build so the harness boots straight
      // into Account Activity (demo mode bypasses the auth redirect).
      appRouter.go(AzRoutes.accountActivity);

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.byType(AccountActivityScreen), findsOneWidget);

      // ── Stable restoration identity on the navigation state ────────
      // The Navigator carries the GoRouter restoration scope...
      final navigator = tester.widget<Navigator>(find.byType(Navigator).first);
      expect(navigator.restorationScopeId, 'azm-router');

      // ...and the account-activity page was deemed restorable with its
      // stable route-name restoration id, so ModalRoute wraps the
      // screen subtree in a RestorationScope.
      final route =
          ModalRoute.of(tester.element(find.byType(AccountActivityScreen)))!;
      // The framework prefixes page-based route restoration ids with
      // 'p+'; the stable identity after the prefix is the route name.
      expect(
        route.restorationScopeId.value,
        'p+${AzRouteNames.accountActivity}',
      );

      final recorded = await scrollDownList(tester);
      expect(recorded, greaterThan(0));

      // Full app restart through the router.
      await tester.restartAndRestore();
      await tester.pumpAndSettle();

      expect(find.byType(AccountActivityScreen), findsOneWidget);
      expect(
        listOffset(tester),
        moreOrLessEquals(recorded, epsilon: 0.5),
        reason: 'the scroll offset must come back through the route-level '
            'RestorationScope after the app restart',
      );
    },
  );

  testWidgets(
    'a SECOND restart restores the offset written during the '
    'reconstructed session (restoration data stays live)',
    (tester) async {
      Widget harness() => const ProviderScope(
            child: MaterialApp(
              restorationScopeId: 'root',
              home: AccountActivityScreen(),
            ),
          );

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      // One drag — stays well below the trailing load-more tile's
      // visibility zone, whose permanently-animating spinner would
      // legitimately prevent quiescence (it is an infinite animation).
      final first = await scrollDownList(tester, drags: 1);
      expect(first, greaterThan(0));

      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(listOffset(tester), moreOrLessEquals(first, epsilon: 0.5));

      // Scroll FURTHER in the reconstructed session.
      final second = await scrollDownList(tester, drags: 1);
      expect(second, greaterThan(first));

      // Restart again — the newest offset, not the first, must restore.
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(
        listOffset(tester),
        moreOrLessEquals(second, epsilon: 0.5),
        reason: 'restoration must reflect the latest recorded offset, not '
            'a stale snapshot',
      );
    },
  );
}
