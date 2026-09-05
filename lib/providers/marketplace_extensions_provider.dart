import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/marketplace_extensions_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/socket_service.dart';

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
  final SocketService _socket;
  final String _tabId;
  late final void Function(Map<String, dynamic>) _dineInSocketListener;
  int _loadGeneration = 0;

  DineInTabNotifier(this._api, this._socket, this._tabId) : super(const AsyncValue.data(null)) {
    _dineInSocketListener = (payload) {
      if (!mounted) return;
      final eventTabId = payload['tabId']?.toString();
      if (eventTabId == null || eventTabId != _tabId) return;
      // Socket payloads are convergence signals only. The canonical API fetch
      // remains the source of truth for the current tab state and payment data.
      loadTab(_tabId);
    };
    _socket.onDineInTabEvent(_dineInSocketListener);
  }

  @override
  void dispose() {
    _socket.removeDineInTabEventListener(_dineInSocketListener);
    super.dispose();
  }

  Future<void> loadTab(String tabId) async {
    if (!mounted || tabId != _tabId) return;
    final generation = ++_loadGeneration;
    state = const AsyncValue.loading();
    try {
      final res = await _api.get('/dine-in/tabs/$tabId');
      final body = jsonDecode(res.body);
      if (!mounted || generation != _loadGeneration) return;
      state = AsyncValue.data(DineInTab.fromJson(body['tab']));
    } catch (e, st) {
      if (!mounted || generation != _loadGeneration) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<DineInTabItem?> addItem(
    String tabId, {
    required String productId,
    Map<String, String> selection = const {},
    int quantity = 1,
  }) async {
    try {
      final res = await _api.post('/dine-in/tabs/$tabId/customer-items', {
        'productId': productId,
        'selection': selection,
        'quantity': quantity,
      });
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final itemJson = body['item'];
      if (itemJson is! Map) throw const FormatException('Dine-in item response is invalid.');
      await loadTab(tabId);
      return DineInTabItem.fromJson(Map<String, dynamic>.from(itemJson));
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> payTab(String tabId, {double? tip}) async {
    if (!mounted || tabId != _tabId) return;
    state = const AsyncValue.loading();
    try {
      await _api.post('/dine-in/tabs/$tabId/pay', {
        if (tip != null) 'tipUsdc': tip,
      });
      await loadTab(tabId);
    } catch (error, stackTrace) {
      // A payment response can be lost after the server commits. Re-read the
      // durable tab once before reporting failure so a CLOSED/paid tab is not
      // presented to the customer as an unsuccessful payment.
      try {
        final res = await _api.get('/dine-in/tabs/$tabId');
        final body = jsonDecode(res.body);
        final latest = DineInTab.fromJson(body['tab']);
        if (latest.id == _tabId && latest.status == 'CLOSED') {
          if (mounted) state = AsyncValue.data(latest);
          return;
        }
      } catch (_) {
        // Preserve the original failure when the authoritative recovery read
        // is also unavailable; the existing timer/socket refresh can converge
        // the screen later.
      }
      if (mounted) state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

final dineInTabProvider = StateNotifierProvider.autoDispose
    .family<DineInTabNotifier, AsyncValue<DineInTab?>, String>(
  (ref, tabId) => DineInTabNotifier(
    ref.watch(apiClientProvider),
    ref.watch(socketServiceProvider),
    tabId,
  )..loadTab(tabId),
);

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