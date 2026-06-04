// =============================================================================
// CHAT TRUST METRICS PROVIDER — Phase UI-6 (2026-05-27)
//
// Powers the persistent trust-line subtitle under a contact's name in the
// chat AppBar:
//
//     <username>
//     ⭐ 4.9 · 120 Completed Transactions    (+ ✓ for verified vendors)
//
// One AsyncNotifier per friendshipId. The chat screen primes it on mount;
// it can also be invalidated when a transaction-affecting socket event
// fires (trade complete, peer transfer fulfilled, ticket closed) so the
// number creeps up in real time. We keep the provider lightweight on
// purpose — the BE endpoint it calls is two parallel COUNTs and one User
// row, so refreshing is cheap.
//
// The metric definition (mirrored from BE chatProfileController.getTrustMetrics):
//   completedTransactions =
//       User.tradesCompleted               (P2P escrow trades)
//     + count(PeerTransfer status=COMPLETED)
//     + count(Ticket       status=CLOSED)
//
// Rationale per the product brief: trust applies to BOTH regular users
// and vendors — a successful transaction always has two committed parties.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/chat_profile_service.dart';

class ChatTrustMetricsState {
  final ChatTrustMetrics? metrics;
  final bool isLoading;
  final String? error;

  const ChatTrustMetricsState({
    this.metrics,
    this.isLoading = false,
    this.error,
  });

  ChatTrustMetricsState copyWith({
    ChatTrustMetrics? metrics,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ChatTrustMetricsState(
      metrics: metrics ?? this.metrics,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatTrustMetricsNotifier extends StateNotifier<ChatTrustMetricsState> {
  ChatTrustMetricsNotifier(this._friendshipId)
      : super(const ChatTrustMetricsState());

  final String _friendshipId;
  final ChatProfileService _service = ChatProfileService.instance;

  /// Initial fetch. Idempotent — calls after the first one are no-ops
  /// while a fetch is in flight or after a successful prime, unless
  /// [force] is set. Use [refresh] to bypass.
  Future<void> primeIfNeeded({bool force = false}) async {
    if (!force && (state.isLoading || state.metrics != null)) return;
    await _fetch();
  }

  /// Force a refresh — used after socket events that move the count
  /// (trade completed, peer transfer fulfilled, ticket closed).
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final metrics = await _service.getTrustMetrics(_friendshipId);
      if (!mounted) return;
      state = ChatTrustMetricsState(metrics: metrics, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

/// Riverpod family — one notifier per friendshipId. The chat screen
/// watches `chatTrustMetricsProvider(friendshipId)` and primes on mount.
final chatTrustMetricsProvider = StateNotifierProvider.family<
    ChatTrustMetricsNotifier, ChatTrustMetricsState, String>(
  (ref, friendshipId) => ChatTrustMetricsNotifier(friendshipId),
);
