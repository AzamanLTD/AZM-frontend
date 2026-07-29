// lib/providers/marketplace_extensions_provider.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS PROVIDER (v2, 2026-07-03)
//
// FIX (2026-07-06): this whole file failed to compile (41 analyzer errors)
// and was never actually used anywhere real in the app (only by the dead
// BusinessAdFeedWidget stub, itself unreferenced anywhere):
//   1. `adFeedProvider` had a typo -- `.autoDispose\n    .AdFeedNotifier, ...`
//      instead of `.autoDispose<AdFeedNotifier, ...>` -- a single wrong
//      character (`.` instead of `<`) that made the parser lose its place
//      for the rest of the file, cascading into 40+ spurious errors.
//   2. Every `res.data[...]` read is a Dio-ism. This app's ApiClient wraps
//      `package:http` and returns `http.Response`, which has no `.data`
//      getter -- fixed to `jsonDecode(res.body)` to match every other
//      working provider/service in this codebase.
// =============================================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/marketplace_extensions_models.dart';
import 'package:azaman/services/api_client.dart';

// ── Follow State ────────────────────────────────────────────────────────────
class FollowNotifier extends StateNotifier<AsyncValue<bool>> {
  final ApiClient _api;
  FollowNotifier(this._api) : super(const AsyncValue.data(false));

  Future<void> checkFollow(String businessProfileId) async {
    final res = await _api.get('/follows/check/$businessProfileId');
    final body = jsonDecode(res.body);
    state = AsyncValue.data(body['isFollowing'] ?? false);
  }

  Future<void> toggle(String businessProfileId) async {
    final current = state.value ?? false;
    state = const AsyncValue.loading();
    try {
      if (current) {
        await _api.delete('/follows/$businessProfileId');
      } else {
        await _api.post('/follows', {'businessProfileId': businessProfileId});
      }
      state = AsyncValue.data(!current);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final followProvider = StateNotifierProvider.autoDispose
    .family<FollowNotifier, AsyncValue<bool>, String>(
  (ref, bizId) => FollowNotifier(ref.watch(apiClientProvider)),
);

// ── Ad Feed ─────────────────────────────────────────────────────────────────
class AdFeedNotifier extends StateNotifier<AsyncValue<List<BusinessAdPost>>> {
  final ApiClient _api;
  AdFeedNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    try {
      final res = await _api.get('/ad-posts/feed?limit=20');
      final body = jsonDecode(res.body);
      final ads = (body['ads'] as List?)
          ?.map((e) => BusinessAdPost.fromJson(e))
          .toList() ?? [];
      state = AsyncValue.data(ads);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final adFeedProvider = StateNotifierProvider.autoDispose<AdFeedNotifier, AsyncValue<List<BusinessAdPost>>>(
  (ref) => AdFeedNotifier(ref.watch(apiClientProvider))..load(),
);

// ── Following list (drives the marketplace status rail / empty state) ──────
class FollowingListNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final ApiClient _api;
  FollowingListNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get('/follows/following?limit=50');
      final body = jsonDecode(res.body);
      final following = (body['following'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      state = AsyncValue.data(following);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final followingListProvider = StateNotifierProvider.autoDispose<FollowingListNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => FollowingListNotifier(ref.watch(apiClientProvider))..load(),
);

// ── Dine-In Tab ─────────────────────────────────────────────────────────────
class DineInTabNotifier extends StateNotifier<AsyncValue<DineInTab?>> {
  final ApiClient _api;
  DineInTabNotifier(this._api) : super(const AsyncValue.data(null));

  Future<void> loadTab(String tabId) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get('/dine-in/tabs/$tabId');
      final body = jsonDecode(res.body);
      state = AsyncValue.data(DineInTab.fromJson(body['tab']));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> payTab(String tabId, {double? tip}) async {
    state = const AsyncValue.loading();
    try {
      await _api.post('/dine-in/tabs/$tabId/pay', {
        if (tip != null) 'tipUsdc': tip,
      });
      await loadTab(tabId);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final dineInTabProvider = StateNotifierProvider.autoDispose
    .family<DineInTabNotifier, AsyncValue<DineInTab?>, String>(
  (ref, tabId) => DineInTabNotifier(ref.watch(apiClientProvider))..loadTab(tabId),
);

// ── Showcase ────────────────────────────────────────────────────────────────
class ShowcaseNotifier extends StateNotifier<AsyncValue<List<BusinessShowcase>>> {
  final ApiClient _api;
  ShowcaseNotifier(this._api) : super(const AsyncValue.loading());

  Future<void> load(String businessProfileId) async {
    try {
      final res = await _api.get('/showcases/$businessProfileId');
      final body = jsonDecode(res.body);
      final items = (body['items'] as List?)
          ?.map((e) => BusinessShowcase.fromJson(e))
          .toList() ?? [];
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final showcaseProvider = StateNotifierProvider.autoDispose
    .family<ShowcaseNotifier, AsyncValue<List<BusinessShowcase>>, String>(
  (ref, bizId) => ShowcaseNotifier(ref.watch(apiClientProvider))..load(bizId),
);
