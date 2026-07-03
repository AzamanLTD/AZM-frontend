// lib/providers/marketplace_extensions_provider.dart
// =============================================================================
// AZAMAN — MARKETPLACE EXTENSIONS PROVIDER (v2, 2026-07-03)
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:azaman/models/marketplace_extensions_models.dart';
import 'package:azaman/providers/marketplace_provider.dart'; // for apiClient
import 'package:azaman/services/api_client.dart';

// ── Follow State ────────────────────────────────────────────────────────────
class FollowNotifier extends StateNotifier<AsyncValue<bool>> {
  final ApiClient _api;
  FollowNotifier(this._api) : super(const AsyncValue.data(false));

  Future<void> checkFollow(String businessProfileId) async {
    final res = await _api.get('/marketplace/follow/check/$businessProfileId');
    state = AsyncValue.data(jsonDecode(res.body)['isFollowing'] ?? false);
  }

  Future<void> toggle(String businessProfileId) async {
    final current = state.value ?? false;
    state = const AsyncValue.loading();
    try {
      if (current) {
        await _api.delete('/marketplace/follow/$businessProfileId');
      } else {
        await _api.post('/marketplace/follow', {'businessProfileId': businessProfileId});
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
      final res = await _api.get('/marketplace/ads/feed?limit=20');
      final ads = (jsonDecode(res.body)['ads'] as List?)
          ?.map((e) => BusinessAdPost.fromJson(e))
          .toList() ?? [];
      state = AsyncValue.data(ads);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final adFeedProvider = StateNotifierProvider.autoDispose
    <AdFeedNotifier, AsyncValue<List<BusinessAdPost>>>(
  (ref) => AdFeedNotifier(ref.watch(apiClientProvider))..load(),
);

// ── Dine-In Tab ─────────────────────────────────────────────────────────────
class DineInTabNotifier extends StateNotifier<AsyncValue<DineInTab?>> {
  final ApiClient _api;
  DineInTabNotifier(this._api) : super(const AsyncValue.data(null));

  Future<void> loadTab(String tabId) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.get('/marketplace/dine-in/tabs/$tabId');
      state = AsyncValue.data(DineInTab.fromJson(jsonDecode(res.body)['tab']));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> payTab(String tabId, {double? tip}) async {
    state = const AsyncValue.loading();
    try {
      await _api.post('/marketplace/dine-in/tabs/$tabId/pay', {
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
      final res = await _api.get('/marketplace/showcase/$businessProfileId');
      final items = (jsonDecode(res.body)['items'] as List?)
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
