// =============================================================================
// MARKETPLACE LIST — honest failure vs. legitimate empty (Workstream F).
//
// A DEAD search request used to render as "No businesses found / Be the
// first to register here" — a failed request masquerading as an empty
// result, with no retry. These tests pin the retired contract at the
// screen level:
//   • a failed search (error set, zero results) shows the FAILURE state,
//     never the empty-state texts; Retry re-fires the real search
//   • a successful search with zero results keeps the legitimate
//     "No businesses found" empty state, no Retry, no failure glyph
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';

/// Sets the HONEST failure state exactly the way the real notifier does
/// after a network/server error: isLoading cleared, error recorded, no
/// results. Counts calls so Retry observability is real.
class _FailingSearchNotifier extends BusinessSearchNotifier {
  _FailingSearchNotifier() : super(BusinessService());

  int calls = 0;

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    calls++;
    state = state.copyWith(isLoading: false, error: 'SocketException: dead');
  }
}

/// A search that succeeds with zero results — the LEGITIMATE empty case.
class _EmptySearchNotifier extends BusinessSearchNotifier {
  _EmptySearchNotifier() : super(BusinessService());

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    state = state.copyWith(isLoading: false, clearError: true);
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  BusinessSearchNotifier notifier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
      child: const MaterialApp(home: MarketplaceHomeScreen()),
    ),
  );
  // Flush the init post-frame search + any animations.
  await tester.pump(const Duration(milliseconds: 600));
}

/// Results are loaded, a later page failed — the honest inline retry
/// (Lead review §5). Loaded results stay visible; the tail retry
/// re-fires the real pagination without dropping results.
class _StalePaginationNotifier extends BusinessSearchNotifier {
  _StalePaginationNotifier() : super(BusinessService());

  int loadMoreCalls = 0;

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    state = state.copyWith(
      isLoading: false,
      clearError: true,
      results: [
        const BusinessProfile(
          id: '1',
          bizId: 'BIZ-1',
          businessName: 'Koko Corner',
          category: 'RETAIL',
          isVerified: true,
          isSuspended: false,
          kybStatus: 'VERIFIED',
          totalEscrows: 0,
          completedEscrows: 0,
          userId: 1,
          totalVolume: 0,
          averageRating: 5,
          username: 'koko_owner',
        ),
      ],
      hasMore: true,
      nextCursor: 'c1',
      // The state exactly as it looks AFTER a failed later-page fetch:
      // results intact, cursor retained, inline pagination failure live.
      loadMoreError: 'dead page',
    );
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
    state = state.copyWith(isLoadingMore: false, loadMoreError: 'dead page');
  }
}

void main() {
  testWidgets(
    'failure: dead search shows the failure state, never the empty lie',
    (tester) async {
      final notifier = _FailingSearchNotifier();
      await _pumpHome(tester, notifier);

      expect(
        find.byKey(const Key('marketplace-search-failure')),
        findsOneWidget,
      );
      expect(find.text("Couldn't load businesses"), findsOneWidget);
      expect(
        find.text('No businesses found'),
        findsNothing,
        reason: 'a failed request must never read as a zero-result success',
      );
      expect(find.text('Be the first to register here'), findsNothing);
    },
  );

  testWidgets('failure: Retry re-fires the real search', (tester) async {
    final notifier = _FailingSearchNotifier();
    await _pumpHome(tester, notifier);
    final before = notifier.calls;

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(notifier.calls, before + 1);
  });

  testWidgets('failed later page: results stay visible with an accessible '
      'inline retry; Retry re-fires the real pagination', (tester) async {
    final notifier = _StalePaginationNotifier();
    // Tall surface: the retry row is the list-tail sentinel of a lazy
    // ListView.builder — it only builds once the viewport can see it.
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, notifier);

    // Loaded results are intact; neither the full-screen failure nor the
    // empty state masquerades as the pagination outcome.
    expect(find.byKey(const Key('marketplace-search-failure')), findsNothing);
    expect(find.text('No businesses found'), findsNothing);
    expect(
      find.text('Koko Corner'),
      findsOneWidget,
      reason: 'already-loaded results stay visible after a page failure',
    );

    // The inline tail retry is rendered with its accessibility semantics.
    final retry = find.byKey(const Key('marketplace-load-more-retry'));
    expect(retry, findsOneWidget);
    // The Semantics live-region wrapper and its merged button text both
    // carry the label — at least one accessible match proves the affordance.
    expect(
      find.bySemanticsLabel(
        RegExp("couldn.t load more.*retry", caseSensitive: false),
      ),
      findsWidgets,
      reason: 'the retry row exposes live-region button semantics',
    );

    await tester.tap(retry);
    await tester.pump();
    expect(
      notifier.loadMoreCalls,
      1,
      reason: 'Retry re-fires the failed pagination itself',
    );

    // Flush any pending screen timers (debounce/animation) before disposal.
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets(
    'empty: successful zero-result search keeps the honest empty state',
    (tester) async {
      await _pumpHome(tester, _EmptySearchNotifier());

      expect(find.byKey(const Key('marketplace-search-failure')), findsNothing);
      expect(find.text('No businesses found'), findsOneWidget);
      expect(find.text("Couldn't load businesses"), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );
}
