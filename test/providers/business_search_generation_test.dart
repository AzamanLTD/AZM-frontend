// =============================================================================
// BUSINESS SEARCH — later-page failures, retry, and request-identity guards
// (Lead review §5).
//
// Provider-level proofs against a scripted BusinessService:
//   • a failed LATER-PAGE fetch keeps loaded results and records
//     loadMoreError (drives the inline tail retry), never the
//     initial-search failure state
//   • retrying the failed pagination appends the SAME page — results are
//     neither dropped nor duplicated
//   • a late response for query A can never replace newer results for
//     query B (generation guard)
//   • a successful search with zero results stays a clean success
// =============================================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';

BusinessProfile _biz(String id) => BusinessProfile(
      id: id,
      bizId: 'BIZ-$id',
      businessName: 'Business $id',
      category: 'RETAIL',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 0,
      completedEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: 0,
      username: 'owner_$id',
    );

typedef _Handler = Future<BusinessPage> Function(String? q, String? cursor);

/// Per-call scripted service: call N uses script[N-1].
class _ScriptedSearchService extends BusinessService {
  final List<_Handler> script = [];
  int calls = 0;

  @override
  Future<BusinessPage> searchBusinesses({
    String? q,
    String? category,
    bool? verified,
    String? subcategory,
    int limit = 20,
    String? cursor,
  }) async {
    assert(calls < script.length, 'unexpected extra service call');
    final handler = script[calls];
    calls++;
    return handler(q, cursor);
  }
}

BusinessPage _page(List<String> ids, {bool hasMore = false, String? cursor}) =>
    (businesses: ids.map(_biz).toList(), hasMore: hasMore, nextCursor: cursor);

void main() {
  test('a failed LATER-PAGE fetch keeps results, records loadMoreError, '
      'and never sets the initial-search error', () async {
    final service = _ScriptedSearchService()
      ..script.add((q, c) async => _page(['a1'], hasMore: true, cursor: 'c1'))
      ..script.add((q, c) async => throw Exception('dead page'));
    final notifier = BusinessSearchNotifier(service);

    await notifier.search('koko');
    await notifier.loadMore();

    expect(notifier.state.results.map((b) => b.bizId), ['BIZ-a1'],
        reason: 'loaded results are never dropped by a pagination failure');
    expect(notifier.state.error, isNull,
        reason: 'a later-page failure is not the initial-search failure');
    expect(notifier.state.loadMoreError, isNotNull,
        reason: 'the inline tail retry is driven by loadMoreError');
    expect(notifier.state.isLoadingMore, isFalse);
  });

  test('retrying the failed pagination appends the same page exactly once',
      () async {
    final service = _ScriptedSearchService()
      ..script.add((q, c) async => _page(['a1'], hasMore: true, cursor: 'c1'))
      ..script.add((q, c) async => throw Exception('dead page'))
      ..script.add((q, c) async => _page(['b1', 'b2'], hasMore: false));
    final notifier = BusinessSearchNotifier(service);

    await notifier.search('koko');
    await notifier.loadMore(); // fails
    await notifier.loadMore(); // retry succeeds

    expect(notifier.state.results.map((b) => b.bizId),
        ['BIZ-a1', 'BIZ-b1', 'BIZ-b2'],
        reason: 'retry appends after the kept results — no drop, no dupe');
    expect(notifier.state.loadMoreError, isNull,
        reason: 'a successful retry clears the inline failure');
    expect(notifier.state.hasMore, isFalse);
  });

  test('out-of-order responses: a late response for query A never replaces '
      'newer results for query B', () async {
    final lateA = Completer<BusinessPage>();
    final service = _ScriptedSearchService()
      ..script.add((q, c) => lateA.future)
      ..script.add((q, c) async => _page(['b1']));
    final notifier = BusinessSearchNotifier(service);

    final searchA = notifier.search('A');
    await Future<void>.delayed(Duration.zero); // A is now awaiting its page

    await notifier.search('B');
    expect(notifier.state.results.map((b) => b.bizId), ['BIZ-b1'],
        reason: 'query B results are live');

    // The STALE response for A finally resolves — it must be discarded.
    lateA.complete(_page(['a1', 'a2']));
    await searchA;

    expect(notifier.state.results.map((b) => b.bizId), ['BIZ-b1'],
        reason: 'a stale query-A page never overwrites query B');
    expect(notifier.state.query, 'B');
  });

  test('a successful zero-result search is a clean success, not a failure',
      () async {
    final service = _ScriptedSearchService()
      ..script.add((q, c) async => _page([], hasMore: false));
    final notifier = BusinessSearchNotifier(service);

    await notifier.search('nothing here');

    expect(notifier.state.results, isEmpty);
    expect(notifier.state.error, isNull);
    expect(notifier.state.loadMoreError, isNull);
    expect(notifier.state.isLoading, isFalse);
  });
}
