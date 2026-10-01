// =============================================================================
// NEW-A — ROUTE-DEPTH CONTRACT TESTS
//
// The depth signal must derive from the matched ROUTE PATTERN, never
// from raw URL segment counting. The contract (see route_depth.dart):
//
//   '/'                    → 0
//   '/transactions'        → 1
//   '/susu/123'            → 1   (parameter value is not a step)
//   '/susu/123/contract'   → 2
//   '/trade/abc'           → 1
//   '/dispute/abc'         → 1
//
// Covered both ways: deep-linked (cold start on the location) and
// natural push/back through the live router stack.
// =============================================================================

import 'package:azaman/router/route_depth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A miniature of the app's real route table — same flat, full-pattern
/// grammar, including the parameterized detail pairs that broke the
/// old segment-counting model.
GoRouter _buildRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/transactions',
          name: 'transactions',
          builder: (context, state) => const Scaffold(body: Text('tx')),
        ),
        GoRoute(
          path: '/susu/:id',
          name: 'susu-detail',
          builder: (context, state) => const Scaffold(body: Text('susu')),
        ),
        GoRoute(
          path: '/susu/:id/contract',
          name: 'susu-contract',
          builder: (context, state) => const Scaffold(body: Text('contract')),
        ),
        GoRoute(
          path: '/trade/:tradeId',
          name: 'trade',
          builder: (context, state) => const Scaffold(body: Text('trade')),
        ),
        GoRoute(
          path: '/dispute/:disputeId',
          name: 'dispute',
          builder: (context, state) => const Scaffold(body: Text('dispute')),
        ),
        GoRoute(
          path: '/queue',
          name: 'queue',
          builder: (context, state) => const Scaffold(body: Text('queue')),
        ),
      ],
    );

Widget _host(GoRouter router, RouteDepthTracker tracker) =>
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => RouteDepthTrackerHost(
        tracker: tracker,
        child: child ?? const SizedBox.shrink(),
      ),
    );

void main() {
  group('routePatternDepth — pattern grammar, not URL segments', () {
    testWidgets('each contract location resolves its documented depth',
        (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      Future<void> at(String location, int expected) async {
        router.go(location);
        await tester.pumpAndSettle();
        expect(effectiveDepth(router), expected,
            reason: '$location should be depth $expected');
      }

      await at('/', 0);
      await at('/transactions', 1);
      await at('/susu/123', 1);
      await at('/susu/123/contract', 2);
      await at('/trade/abc', 1);
      await at('/dispute/abc', 1);
      await at('/queue?queueId=q1&position=2&adId=3', 1);
    });

    testWidgets('parameter placeholders never count as steps', (tester) async {
      final router = _buildRouter();
      addTearDown(router.dispose);

      final patterns = {
        '/': 0,
        '/transactions': 1,
        '/susu/:id': 1,
        '/susu/:id/contract': 2,
        '/trade/:tradeId': 1,
        '/dispute/:disputeId': 1,
        '/queue': 1,
      };
      for (final route in router.configuration.routes.whereType<GoRoute>()) {
        expect(routePatternDepth(route), patterns[route.path],
            reason: "pattern '${route.path}' has wrong depth");
      }
    });
  });

  group('RouteDepthTracker — deep-linked parameterized detail', () {
    testWidgets('cold start on /susu/123 reports depth 1, not 2',
        (tester) async {
      final router = _buildRouter(initialLocation: '/susu/123');
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      expect(tracker.depth, 1,
          reason: 'deep-linked susu detail is one level below home');
      expect(tracker.routeNames, ['susu-detail']);
    });

    testWidgets('cold start on /susu/123/contract reports depth 2',
        (tester) async {
      final router = _buildRouter(initialLocation: '/susu/123/contract');
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      expect(tracker.depth, 2);
      expect(tracker.routeNames, ['susu-contract']);
    });

    testWidgets('cold start on /trade/abc reports depth 1', (tester) async {
      final router = _buildRouter(initialLocation: '/trade/abc');
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      expect(tracker.depth, 1);
      expect(tracker.routeNames, ['trade']);
    });
  });

  group('RouteDepthTracker — natural push/back through the live stack', () {
    testWidgets('root → 0, push detail → 1, back → 0', (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();
      expect(tracker.depth, 0);
      expect(tracker.routeNames, ['home']);

      router.push('/susu/123');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1,
          reason: 'natural push of the susu detail is depth 1');
      expect(tracker.routeNames, ['home', 'susu-detail']);

      router.pop();
      await tester.pumpAndSettle();
      expect(tracker.depth, 0);
      expect(tracker.routeNames, ['home']);
    });

    testWidgets(
        'depth follows the current route, not the stack length',
        (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      // home → /transactions → /susu/123: the CURRENT page is the susu
      // detail; its structural depth is 1 regardless of stack length.
      router.push('/transactions');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1);

      router.push('/susu/123');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1,
          reason: 'current route is /susu/:id → depth 1, stack has 3 pages');

      router.pop();
      await tester.pumpAndSettle();
      expect(tracker.depth, 1, reason: 'back to /transactions is depth 1');

      router.pop();
      await tester.pumpAndSettle();
      expect(tracker.depth, 0, reason: 'back home is depth 0');
    });

    testWidgets('nested parameterized detail via natural push → 2',
        (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      router.push('/susu/123');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1);

      router.push('/susu/123/contract');
      await tester.pumpAndSettle();
      expect(tracker.depth, 2,
          reason: 'contract under a parameterized parent is depth 2');

      router.pop();
      await tester.pumpAndSettle();
      expect(tracker.depth, 1);
    });

    testWidgets('flat route pushes keep the documented 1', (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      router.push('/trade/abc');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1);

      router.push('/dispute/abc');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1);
    });

    testWidgets('query-bearing pushes do not inflate depth', (tester) async {
      final router = _buildRouter();
      final tracker = RouteDepthTracker(router);
      addTearDown(tracker.dispose);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(router, tracker));
      await tester.pumpAndSettle();

      router.push('/queue?queueId=q1&position=2&adId=3');
      await tester.pumpAndSettle();
      expect(tracker.depth, 1,
          reason: 'the /queue pattern is depth 1; query is not structure');
    });
  });
}
