// =============================================================================
// MIX FEED SURFACE — scan-budget boundary (final acceptance pass 2026-10-19).
//
// The server's window-filter scan is bounded per request (backend runQuery
// walks at most MAX_ROUNDS batches of where-eligible rows), so a page can
// legitimately return `items: []` with a NON-NULL nextCursor. These tests
// pin the two halves of the client continuation contract:
//   • the first page AUTO-FOLLOWS empty cursor pages (notifier walk) until
//     offers appear — the surface renders the feed, not the empty state;
//   • if the notifier's continuation budget itself is exhausted while a
//     cursor remains, the honest empty state carries an explicit
//     "Show more" continuation affordance — never a dead end — and tapping
//     it surfaces the eligible items waiting beyond the scan window.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/experience/gateways/marketplace_mix_gateway.dart';
import 'package:azaman/marketplace/mix/mix_models.dart';
import 'package:azaman/providers/marketplace_mix_provider.dart';
import 'package:azaman/widgets/marketplace/discovery/mix_feed_surface.dart';

class _FakeGateway implements MarketplaceMixGateway {
  _FakeGateway(this.behavior);

  final Future<MixDiscoveryPage> Function(String? cursor, int call) behavior;
  int calls = 0;

  @override
  Set<MixCapability> get supportedCapabilities => const {
    MixCapability.itemStoreInteractions,
  };

  @override
  Future<MixDiscoveryPage> fetchItems({
    String? category,
    String? q,
    List<String> taxonomies = const [],
    String? city,
    String? region,
    int? limit,
    String? cursor,
  }) async {
    calls += 1;
    await Future<void>.delayed(Duration.zero);
    return behavior(cursor, calls);
  }
}

MixDiscoveryPage _page(List<String> ids, String? next) => (
  offers: ids
      .map(
        (id) => MixOffer(
          productId: id,
          businessId: 'bp-$id',
          bizId: 'BIZ-$id',
          businessName: 'Store $id',
          businessCategory: 'FOOD_BEVERAGE',
          name: 'Item $id',
          price: const MixOfferPrice.fixedGhs('10.00'),
        ),
      )
      .toList(),
  nextCursor: next,
);

Future<void> _pumpSurface(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [marketplaceMixGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: Scaffold(body: MixFeedSurface(onOpenStore: _noop, bottomPadding: 0))),
    ),
  );
  // The initial load is the HOST screen's job (screen entry calls load());
  // this test drives the real notifier through the widget's scope.
  final ctx = tester.element(find.byType(MixFeedSurface));
  ProviderScope.containerOf(ctx)
      .read(marketplaceMixProvider.notifier)
      .load();
  // pumpAndSettle never returns for this surface (decorative animations run
  // continuously), so pump explicit bounded frames instead — enough for the
  // full first-page walk to resolve.
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _noop(MixOffer offer) {}

void main() {
  testWidgets(
    'an empty first page WITH a cursor is auto-followed — offers appear, '
    'the empty state never renders',
    (tester) async {
      final g = _FakeGateway((cursor, call) async {
        if (call == 1) return _page([], 'CUR-1');
        return _page(['a', 'b'], null);
      });
      await _pumpSurface(tester, g);

      expect(g.calls, 2, reason: 'the initial page plus exactly one bounded follow-up');
      expect(find.byKey(const ValueKey('mix_feed')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_empty')), findsNothing);
      expect(find.byKey(const ValueKey('mix_empty_continue')), findsNothing);
      expect(find.text('Item a'), findsOneWidget);
      expect(find.text('Item b'), findsOneWidget);
    },
  );

  testWidgets(
    'a continuation-budget exhaustion renders the honest empty state WITH a '
    '"Show more" affordance — tapping it surfaces the waiting offers',
    (tester) async {
      // Every auto-follow page is empty with a cursor until the notifier's
      // continuation budget (kMaxFirstPageContinuations) is exhausted; the
      // NEXT request — the surface affordance's — finally has offers.
      final g = _FakeGateway((cursor, call) async {
        if (call <= 1 + MarketplaceMixNotifier.kMaxFirstPageContinuations) {
          return _page([], 'CUR-$call');
        }
        return _page(['x'], null);
      });
      await _pumpSurface(tester, g);

      // The budget is a hard limit: initial request + exactly the limit.
      expect(g.calls, 1 + MarketplaceMixNotifier.kMaxFirstPageContinuations);
      // The honest empty state — with the continuation affordance, not a
      // dead end.
      expect(find.byKey(const ValueKey('mix_empty')), findsOneWidget);
      final affordance = find.byKey(const ValueKey('mix_empty_continue'));
      expect(affordance, findsOneWidget);
      expect(find.text('Show more'), findsOneWidget);

      // Tapping the affordance continues the walk — the eligible items
      // beyond the scan window surface without any category/filter change.
      await tester.tap(affordance);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.calls, 2 + MarketplaceMixNotifier.kMaxFirstPageContinuations);
      expect(find.byKey(const ValueKey('mix_feed')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_empty')), findsNothing);
      expect(find.text('Item x'), findsOneWidget);
    },
  );

  testWidgets(
    'a stalled cursor renders the explicit stalled panel (retry/refresh) — '
    'never a Show more that resubmits the same cursor',
    (tester) async {
      // The cursor repeats: the automatic walk stops at the first repeat
      // and flags the stall.
      final g = _FakeGateway((cursor, call) async => _page([], 'CUR-REPEAT'));
      await _pumpSurface(tester, g);

      expect(g.calls, 2, reason: 'page 1 plus one follow-up before the repeat');
      // The STALLED panel, not the Show more affordance.
      expect(find.byKey(const ValueKey('mix_stalled_notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_stalled_retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_stalled_refresh')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_empty_continue')), findsNothing);
      expect(find.text('Show more'), findsNothing);

      // Refresh feed: a fresh walk — which honestly stalls again on the
      // same repeating gateway, bounded (no loop).
      await tester.tap(find.byKey(const ValueKey('mix_stalled_refresh')));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(g.calls, 4, reason: 'the refresh walk is bounded again');
      expect(
        find.byKey(const ValueKey('mix_stalled_notice')),
        findsOneWidget,
        reason: 'still honestly stalled — no invented items',
      );
    },
  );

  testWidgets(
    'a multi-request first-page walk shows the truthful searching feedback '
    'line during the walk (never a silent skeleton)',
    (tester) async {
      final secondPage = Completer<MixDiscoveryPage>();
      var calls = 0;
      final g = _FakeGateway((cursor, call) async {
        calls += 1;
        if (calls == 1) return _page([], 'CUR-1');
        // The follow-up request hangs until the test completes it — the
        // walk is visibly in progress.
        return secondPage.future;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [marketplaceMixGatewayProvider.overrideWithValue(g)],
          child: const MaterialApp(
            home: Scaffold(
              body: MixFeedSurface(onOpenStore: _noop, bottomPadding: 0),
            ),
          ),
        ),
      );
      final ctx = tester.element(find.byType(MixFeedSurface));
      final container = ProviderScope.containerOf(ctx);
      container.read(marketplaceMixProvider.notifier).load();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Page 1 is empty with a cursor and the follow-up is in flight: the
      // loading state says what it is doing — searching further — instead
      // of a silent skeleton for the whole worst case.
      expect(calls, 2);
      expect(find.byKey(const ValueKey('mix_loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_searching_wide')), findsOneWidget);

      // The follow-up resolves with the offers — the feed renders.
      secondPage.complete(_page(['x'], null));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('mix_feed')), findsOneWidget);
      expect(find.text('Item x'), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_searching_wide')), findsNothing);
    },
  );

  testWidgets(
    'a stalled continuation on a NON-empty feed renders the compact stalled '
    'tail and keeps the feed intact',
    (tester) async {
      final g = _FakeGateway((cursor, call) async {
        if (call == 1) return _page(['a'], 'CUR-A');
        // Manual continuation submits CUR-A and gets the SAME cursor back.
        return _page([], 'CUR-A');
      });
      await _pumpSurface(tester, g);
      expect(find.text('Item a'), findsOneWidget);

      // Drive the manual continuation through the widget's own scope.
      // (Fire-and-forget like the harness load(): the fake-async gateway
      // future only advances while frames pump.)
      final ctx = tester.element(find.byType(MixFeedSurface));
      ProviderScope.containerOf(ctx)
          .read(marketplaceMixProvider.notifier)
          .loadMore();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The feed is untouched and the explicit compact stalled tail shows.
      expect(g.calls, 2);
      expect(find.text('Item a'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mix_stalled_tail_notice')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mix_stalled_retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('mix_stalled_refresh')), findsOneWidget);
      // No skeleton stuck in loadingMore, no infinite tail.
      expect(g.calls, 2, reason: 'the stall blocks any further continuation');
    },
  );

  testWidgets(
    'true exhaustion is an honest terminal empty state — no cursor, no affordance',
    (tester) async {
      // The automatic walk's first follow-up page is empty with a NULL
      // cursor: the source is exhausted. Nothing more to follow.
      final g = _FakeGateway((cursor, call) async {
        if (call == 1) return _page([], 'CUR-1');
        return _page([], null);
      });
      await _pumpSurface(tester, g);

      expect(g.calls, 2, reason: 'the initial page plus its one follow-up');
      expect(find.byKey(const ValueKey('mix_empty')), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
      // Terminal: no cursor survives, so NO continuation affordance.
      expect(find.byKey(const ValueKey('mix_empty_continue')), findsNothing);
      expect(find.text('Show more'), findsNothing);
    },
  );
}
