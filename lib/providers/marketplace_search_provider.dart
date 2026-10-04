// =============================================================================
// AZAMAN — UNIFIED MARKETPLACE SEARCH STATE
//
// The explore screen today, and the in-pill nav search tomorrow, drive ONE
// state. `MarketplaceHomeScreen` no longer keeps `_searchExpanded` + a local
// debounce; it watches this notifier. Commit (`submit`) pushes into the
// EXISTING `businessSearchProvider` plumbing.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';

enum MarketplaceSearchScope { marketplace, world, store }

class MarketplaceSearchState {
  final String text;
  final bool focused;
  final MarketplaceSearchScope scope;

  /// When `scope == world` or `store`: the world wire (`FOOD_BEVERAGE`, …).
  final String? worldWire;

  /// When `scope == store`.
  final String? storeBizId;

  /// Last 8 submitted queries, persisted.
  final List<String> recent;

  /// Derived from [text]; never persisted.
  final List<String> suggestions;

  const MarketplaceSearchState({
    this.text = '',
    this.focused = false,
    this.scope = MarketplaceSearchScope.marketplace,
    this.worldWire,
    this.storeBizId,
    this.recent = const [],
    this.suggestions = const [],
  });

  bool get isActive => focused || text.isNotEmpty;

  MarketplaceSearchState copyWith({
    String? text,
    bool? focused,
    MarketplaceSearchScope? scope,
    Object? worldWire = _unset,
    Object? storeBizId = _unset,
    List<String>? recent,
    List<String>? suggestions,
  }) =>
      MarketplaceSearchState(
        text: text ?? this.text,
        focused: focused ?? this.focused,
        scope: scope ?? this.scope,
        worldWire: worldWire == _unset ? this.worldWire : worldWire as String?,
        storeBizId:
            storeBizId == _unset ? this.storeBizId : storeBizId as String?,
        recent: recent ?? this.recent,
        suggestions: suggestions ?? this.suggestions,
      );

  static const Object _unset = Object();
}

class MarketplaceSearchNotifier extends StateNotifier<MarketplaceSearchState> {
  MarketplaceSearchNotifier(this.ref) : super(const MarketplaceSearchState()) {
    _loadRecent();
  }

  final Ref ref;
  static const kRecentKey = 'az_marketplace_recent_searches';
  static const kMaxRecent = 8;

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      state = state.copyWith(recent: prefs.getStringList(kRecentKey) ?? const []);
    } catch (_) {
      // Preferences unavailable (tests without mocks, platform failure):
      // recents simply stay empty. Search still works.
    }
  }

  /// Changing scope clears the text — a query typed for one world does not
  /// leak into another.
  void setScope(MarketplaceSearchScope scope,
      {String? worldWire, String? storeBizId}) {
    state = state.copyWith(
      scope: scope,
      worldWire: worldWire,
      storeBizId: storeBizId,
      text: '',
      focused: false,
      suggestions: const [],
    );
  }

  void focus(bool value) {
    if (state.focused == value) return;
    state = state.copyWith(focused: value);
  }

  void changed(String text) {
    state = state.copyWith(text: text, suggestions: _suggest(text));
  }

  /// Commit: persist recent, push into the existing search plumbing.
  ///
  /// Pass `fetch: false` when the caller has already run the query through
  /// its own plumbing (the explore screen adds view mode / verified filters)
  /// and only wants the recent-search bookkeeping.
  Future<void> submit({bool fetch = true}) async {
    final q = state.text.trim();
    if (q.isEmpty) return;

    // Capture the committed search context before the persistence await. A
    // scope can change while SharedPreferences is completing; the request
    // must never silently switch to the newer scope.
    final committedScope = state.scope;
    final committedWorldWire = state.worldWire;
    final recent = [q, ...state.recent.where((r) => r != q)].take(kMaxRecent).toList();
    state = state.copyWith(recent: recent, focused: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kRecentKey, recent);
    } catch (_) {}
    if (!fetch) return;
    switch (committedScope) {
      case MarketplaceSearchScope.marketplace:
      case MarketplaceSearchScope.world:
        await ref
            .read(businessSearchProvider.notifier)
            .search(q, category: committedWorldWire);
      case MarketplaceSearchScope.store:
        // Store-scoped search filters the store's already-loaded catalog
        // locally (verticals, 03 §1.3); nothing to fetch.
        break;
    }
  }

  void clear() {
    state = state.copyWith(text: '', focused: false, suggestions: const []);
  }

  List<String> _suggest(String text) {
    if (text.length < 2) return state.recent.take(4).toList();
    final lower = text.toLowerCase();
    final cats = BusinessCategories.values
        .where((c) => c.label.toLowerCase().contains(lower))
        .map((c) => c.label);
    final names = ref
        .read(businessSearchProvider)
        .results
        .where((b) => b.businessName.toLowerCase().contains(lower))
        .map((b) => b.businessName)
        .take(5);
    return {...cats, ...names}.toList();
  }
}

final marketplaceSearchProvider =
    StateNotifierProvider<MarketplaceSearchNotifier, MarketplaceSearchState>(
  (ref) => MarketplaceSearchNotifier(ref),
);