// =============================================================================
// AZAMAN — AZM REWARD PROVIDER (Phase E1-FE)
//
// Riverpod state layer for AZM loyalty-point earn history and summary.
// Consumed by the AzmRewardScreen and the home dashboard's AZM tile.
//
// State is refreshed:
//   - On screen mount (via .primeIfNeeded())
//   - On pull-to-refresh
//   - On `azm_reward` socket event (real-time credit notifications)
//   - On pagination (load-more appends to existing list)
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/azm_reward_service.dart';

// ─── State ───────────────────────────────────────────────────────────────────

class AzmRewardState {
  final List<AzmRewardEntry> rewards;
  final AzmSummary? summary;
  final AzmRates? rates;
  final String? nextCursor;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String? error;

  /// Most recent real-time reward (from socket) — used for toast/celebration
  final AzmRewardEntry? lastRealtimeReward;

  /// Friends leaderboard (2026-07-06) — loaded alongside summary/rates on
  /// refresh. Kept separate from `summary` since it's a distinct concept
  /// (social ranking vs. personal totals) with its own loading semantics.
  final AzmFriendsLeaderboard leaderboard;

  const AzmRewardState({
    this.rewards = const [],
    this.summary,
    this.rates,
    this.nextCursor,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.lastRealtimeReward,
    this.leaderboard = AzmFriendsLeaderboard.empty,
  });

  AzmRewardState copyWith({
    List<AzmRewardEntry>? rewards,
    AzmSummary? summary,
    AzmRates? rates,
    String? nextCursor,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? error,
    AzmRewardEntry? lastRealtimeReward,
    AzmFriendsLeaderboard? leaderboard,
  }) {
    return AzmRewardState(
      rewards: rewards ?? this.rewards,
      summary: summary ?? this.summary,
      rates: rates ?? this.rates,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error,
      lastRealtimeReward: lastRealtimeReward ?? this.lastRealtimeReward,
      leaderboard: leaderboard ?? this.leaderboard,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────

class AzmRewardNotifier extends StateNotifier<AzmRewardState> {
  AzmRewardNotifier() : super(const AzmRewardState());

  bool _primed = false;

  /// Load initial data (history + summary + rates). Idempotent.
  Future<void> primeIfNeeded() async {
    if (_primed) return;
    _primed = true;
    await refresh();
  }

  /// Full refresh — re-fetch everything from page 1.
  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);

    try {
      final results = await Future.wait([
        azmRewardService.getHistory(limit: 20),
        azmRewardService.getSummary(),
        azmRewardService.getRates(),
        azmRewardService.getFriendsLeaderboard(limit: 10),
      ]);

      final historyResult = results[0] as ({List<AzmRewardEntry> rewards, String? nextCursor, bool hasMore});
      final summary = results[1] as AzmSummary;
      final rates = results[2] as AzmRates;
      final leaderboard = results[3] as AzmFriendsLeaderboard;

      state = AzmRewardState(
        rewards: historyResult.rewards,
        summary: summary,
        rates: rates,
        nextCursor: historyResult.nextCursor,
        hasMore: historyResult.hasMore,
        loading: false,
        leaderboard: leaderboard,
      );
    } catch (e) {
      debugPrint('[AzmRewardNotifier] refresh error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Load next page of history (append to existing list).
  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.nextCursor == null) return;

    state = state.copyWith(loadingMore: true);

    try {
      final result = await azmRewardService.getHistory(
        cursor: state.nextCursor,
        limit: 20,
      );

      state = state.copyWith(
        rewards: [...state.rewards, ...result.rewards],
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      debugPrint('[AzmRewardNotifier] loadMore error: $e');
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Called when a real-time `azm_reward` socket event arrives.
  /// Prepends the new reward to the list and updates the summary balance.
  void onRealtimeReward({
    required double azmBalance,
    required double awarded,
    required String source,
    required String reason,
  }) {
    final newEntry = AzmRewardEntry(
      id: 'rt_${DateTime.now().millisecondsSinceEpoch}',
      amount: awarded,
      reason: reason,
      source: source,
      balanceAfter: azmBalance,
      createdAt: DateTime.now(),
    );

    final updatedSummary = state.summary != null
        ? AzmSummary(
            totalEarned: state.summary!.totalEarned + awarded,
            currentBalance: azmBalance,
            bySource: state.summary!.bySource,
            // FIX (2026-07-06): rebuilding AzmSummary here previously
            // dropped loginStreak/lastLoginAt back to their defaults on
            // every single real-time reward event -- the streak display
            // would flicker to 0 any time a reward socket event landed.
            loginStreak: state.summary!.loginStreak,
            lastLoginAt: state.summary!.lastLoginAt,
          )
        : null;

    state = state.copyWith(
      rewards: [newEntry, ...state.rewards],
      summary: updatedSummary,
      lastRealtimeReward: newEntry,
    );
  }

  /// Clear the last realtime reward (after showing toast/celebration)
  void clearLastRealtimeReward() {
    state = state.copyWith(lastRealtimeReward: null);
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

final azmRewardProvider =
    StateNotifierProvider<AzmRewardNotifier, AzmRewardState>((ref) {
  return AzmRewardNotifier();
});
