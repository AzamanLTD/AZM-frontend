// =============================================================================
// PR-B — the ONE back contract (router/back_navigation.dart)
//
// Proves the precedence on the REAL route stack, with BOTH navigation
// systems live (GoRouter pages AND imperative routes on the same root
// navigator):
//
//   1. transient surface on top (dialog) → pops ONLY the dialog, the
//      underlying screen survives untouched (one consumption per action);
//   2. imperative route on top → pops the imperative route via the root
//      navigator; the underlying router page keeps its scroll position;
//   3. router page on top → pops exactly one router page;
//   4. nothing under the top (deep-link-style stack) → the honest root
//      fallback: go home, never a phantom pop;
//   5. detail → list (router route), back → the list's scroll offset is
//      exactly what it was;
//   6. detail → list (imperative route), back → same preservation;
//   7. rapid repeated back actions consume exactly one level each.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/router/back_navigation.dart';
import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/top_route_observer.dart';

/// A list page whose outermost scrollable keeps a controller we can read.
class _ListPage extends StatefulWidget {
  const _ListPage({required this.onPushDetail});

  final VoidCallback onPushDetail;

  @override
  State<_ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<_ListPage> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('list-scaffold'),
      floatingActionButton: FloatingActionButton(
        key: const Key('open-detail-fab'),
        onPressed: widget.onPushDetail,
        child: const Icon(Icons.open_in_new),
      ),
      body: ListView.builder(
        controller: _controller,
        itemCount: 120,
        itemBuilder: (_, i) => ListTile(
          key: Key('list-row-$i'),
          title: Text('ROW $i'),
        ),
      ),
    );
  }
}

GoRouter _testRouter({VoidCallback? onDetailTapped}) {
  late final GoRouter router;
  void pushDetail() {
    onDetailTapped?.call();
    router.push('/detail');
  }

  router = GoRouter(
    initialLocation: '/list',
    observers: [topRouteObserver],
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (_, __) => const Scaffold(
          key: Key('home-scaffold'),
          body: Center(child: Text('HOME ROOT')),
        ),
      ),
      GoRoute(
        path: '/list',
        name: 'list',
        builder: (_, __) => _ListPage(onPushDetail: pushDetail),
      ),
      GoRoute(
        path: '/detail',
        name: 'detail',
        builder: (_, __) => const Scaffold(
          key: Key('detail-scaffold'),
          body: Center(child: Text('DETAIL ROUTER PAGE')),
        ),
      ),
    ],
  );
  return router;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  VoidCallback? onDetailTapped,
}) async {
  final router = _testRouter(onDetailTapped: onDetailTapped);
  final tracker = RouteDepthTracker(router);
  addTearDown(tracker.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        // Mirror the app: the tracker host wraps navigator + any chrome.
        builder: (context, child) => RouteDepthTrackerHost(
          tracker: tracker,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Runs the back contract from a context under the tracker host (any
/// element inside the app qualifies — use the Scaffold of [marker]).
Future<void> _runBack(WidgetTester tester, Key marker) async {
  AzBackNavigation.handleBack(
    tester.element(find.byKey(marker, skipOffstage: false)),
  );
}

double _listOffset(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('list-scaffold')),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  return position.pixels;
}

void main() {
  testWidgets(
      'a dialog on top is dismissed alone — the underlying page survives',
      (tester) async {
    var detailPushed = false;
    await _pumpApp(tester, onDetailTapped: () => detailPushed = true);

    // Scroll the list, then cover the page with a dialog.
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    final offsetBefore = _listOffset(tester);
    expect(offsetBefore, greaterThan(0));

    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(DialogRoute<void>(
      context: tester.element(find.byKey(const Key('list-scaffold'))),
      builder: (_) => const AlertDialog(
        key: Key('test-dialog'),
        content: Text('DIALOG BODY'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-dialog')), findsOneWidget);
    expect(topRouteObserver.topRouteIsRouterPage, isFalse);

    // ONE back action: the dialog pops, nothing else does.
    await _runBack(tester, const Key('list-scaffold'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test-dialog')), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
    expect(_listOffset(tester), offsetBefore, // scroll survived intact
        reason: 'the back action must not touch the underlying screen');
    expect(detailPushed, isFalse);
  });

  testWidgets(
      'an imperative route on top is popped via the root navigator, '
      'preserving the underlying router page scroll',
      (tester) async {
    await _pumpApp(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    final offsetBefore = _listOffset(tester);
    expect(offsetBefore, greaterThan(200));

    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        key: Key('imperative-detail'),
        body: Center(child: Text('DETAIL IMPERATIVE PAGE')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('imperative-detail')), findsOneWidget);

    await _runBack(tester, const Key('imperative-detail'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('imperative-detail')), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
    expect(_listOffset(tester), offsetBefore,
        reason: 'imperative back must preserve the list position');
  });

  testWidgets('a router page on top pops exactly one router page',
      (tester) async {
    var pushes = 0;
    await _pumpApp(tester, onDetailTapped: () => pushes++);

    // Open the router detail from the list (the always-visible FAB).
    await tester.tap(find.byKey(const Key('open-detail-fab')));
    await tester.pumpAndSettle();
    expect(pushes, 1);
    expect(find.text('DETAIL ROUTER PAGE'), findsOneWidget);

    await _runBack(tester, const Key('detail-scaffold'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL ROUTER PAGE'), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
  });

  testWidgets(
      'detail → list back preserves the list scroll position (router route)',
      (tester) async {
    await _pumpApp(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    final offsetBefore = _listOffset(tester);

    await tester.tap(find.byKey(const Key('open-detail-fab')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL ROUTER PAGE'), findsOneWidget);

    await _runBack(tester, const Key('detail-scaffold'));
    await tester.pumpAndSettle();

    expect(_listOffset(tester), offsetBefore,
        reason: 'returning from a detail page must not reset the list');
  });

  testWidgets(
      'a deep-link-style stack (nothing to pop) backs out to the honest root',
      (tester) async {
    // Cold stack: the list page IS the base — nothing under it.
    await _pumpApp(tester);

    await _runBack(tester, const Key('list-scaffold'));
    await tester.pumpAndSettle();

    // No phantom pop, no crash: the fallback targets the CANONICAL home
    // route — the honest root, replacing the deep-link stack.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(nav.widget.pages.length, 1);
    expect(find.byKey(const Key('home-scaffold')), findsOneWidget);
    expect(find.byKey(const Key('list-scaffold')), findsNothing);
  });

  testWidgets('rapid repeated back actions consume one level each',
      (tester) async {
    var detailTaps = 0;
    await _pumpApp(tester, onDetailTapped: () => detailTaps++);

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    // Stack: list + imperative detail.
    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        key: Key('imperative-detail'),
        body: Center(child: Text('DETAIL IMPERATIVE PAGE')),
      ),
    ));
    await tester.pumpAndSettle();

    // Back, back — no settle between them. The FIRST press consumes
    // exactly the imperative route (its didPop has already fired: the
    // top-route kind observer reports the router page as top again,
    // while the route's exit animation is still draining). The SECOND
    // press then pops the deep-link base into the honest root fallback
    // without crashing or double-consuming.
    await _runBack(tester, const Key('imperative-detail'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(topRouteObserver.topRouteIsRouterPage, isTrue,
        reason: 'press one consumed exactly the imperative route');
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);

    await _runBack(tester, const Key('list-scaffold'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-scaffold')), findsOneWidget,
        reason: 'press two fell through to the honest root fallback');
    expect(detailTaps, 0); // nothing else was touched
  });

  // ─────────────────────────────────────────────────────────────────────
  // THE PLATFORM BACK ACTION (closeout): the same contract, exercised
  // through the REAL system-back dispatch — NOT the helper. On a real
  // phone the Android back gesture resolves through WidgetsBinding's
  // pop-route dispatch into the router delegate's popRoute() (for
  // MaterialApp.router: GoRouter -> root Navigator.maybePop). These
  // tests drive exactly that path with handlePopRoute(), so the visible
  // chevron and the phone's back gesture are proven to share ONE
  // route-stack contract. The OS gesture itself (predictive-back
  // preview) is not simulable in a widget test — that is documented as
  // a limitation, not assumed away.
  // ─────────────────────────────────────────────────────────────────────

  testWidgets(
      'PLATFORM back: a dialog on top is dismissed alone, the page and '
      'its scroll survive', (tester) async {
    await _pumpApp(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    final offsetBefore = _listOffset(tester);

    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(DialogRoute<void>(
      context: tester.element(find.byKey(const Key('list-scaffold'))),
      builder: (_) => const AlertDialog(
        key: Key('test-dialog'),
        content: Text('DIALOG BODY'),
      ),
    ));
    await tester.pumpAndSettle();

    // The REAL platform dispatch: handled == true means the app consumed
    // it (the dialog popped); the engine would NOT have exited.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'the platform back was consumed in-app');
    expect(find.byKey(const Key('test-dialog')), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
    expect(_listOffset(tester), offsetBefore,
        reason: 'the platform back must not touch the underlying screen');
  });

  testWidgets(
      'PLATFORM back: an imperative route is popped, the router page '
      'keeps its scroll', (tester) async {
    await _pumpApp(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    final offsetBefore = _listOffset(tester);

    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        key: Key('imperative-detail'),
        body: Center(child: Text('DETAIL IMPERATIVE PAGE')),
      ),
    ));
    await tester.pumpAndSettle();

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byKey(const Key('imperative-detail')), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
    expect(_listOffset(tester), offsetBefore,
        reason: 'platform back must preserve the list position');
  });

  testWidgets(
      'PLATFORM back: a router page on top pops exactly one router page',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('open-detail-fab')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL ROUTER PAGE'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('DETAIL ROUTER PAGE'), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget,
        reason: 'exactly ONE router page popped — the list below survived');
  });

  testWidgets(
      'PLATFORM back: rapid repeated backs consume one level each '
      '(dialog then its page)', (tester) async {
    await _pumpApp(tester);

    // Stack: list + imperative detail + dialog on top.
    Navigator.of(
      tester.element(find.byKey(const Key('list-scaffold'))),
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        key: Key('imperative-detail'),
        body: Center(child: Text('DETAIL IMPERATIVE PAGE')),
      ),
    ));
    await tester.pumpAndSettle();
    Navigator.of(
      tester.element(find.byKey(const Key('imperative-detail'))),
      rootNavigator: true,
    ).push(DialogRoute<void>(
      context: tester.element(find.byKey(const Key('imperative-detail'))),
      builder: (_) => const AlertDialog(
        key: Key('test-dialog'),
        content: Text('DIALOG BODY'),
      ),
    ));
    await tester.pumpAndSettle();

    // ONE platform back: the dialog ONLY — the page under it survives.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-dialog')), findsNothing);
    expect(find.byKey(const Key('imperative-detail')), findsOneWidget,
        reason: 'a single back gesture must not double-apply');

    // The next platform back pops the imperative page.
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('imperative-detail')), findsNothing);
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
  });

  testWidgets(
      'PLATFORM back on a cold deep-link stack is honestly unhandled '
      '(the OS keeps its exit behavior — no fabricated route)',
      (tester) async {
    await _pumpApp(tester);
    // The list page IS the base of the stack — nothing under it.

    // handlePopRoute returning FALSE is the engine's honest signal:
    // the app has nothing to pop, so the PLATFORM decides (predictive
    // back: leave the app). The app must NOT fabricate a "previous"
    // route here. The visible chevron's in-app fallback (canonical
    // home) is a separate affordance, tested above.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isFalse,
        reason: 'a cold stack has nowhere to return: the platform back '
            'stays with the platform, and no route is invented');
    expect(find.byKey(const Key('list-scaffold')), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(nav.widget.pages.length, 1,
        reason: 'the stack was not rewritten or fabricated');
  });
}
