// =============================================================================
// AZAMAN — AZM SPEND PROVIDER (Phase E2-FE)
//
// Riverpod state layer for AZM loyalty-point spend features.
// Consumed by the WithdrawalScreen (fee discount) and VendorDashboard (ad boost).
//
// State is refreshed:
//   - On screen mount (via .primeIfNeeded())
//   - On `azm_spend` socket event (real-time debit notification)
//   - On successful spend action (optimistic update)
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/azm_spend_service.dart';

// ── State ────────────────────────────────────────────────────────────────────

class AzmSpendState {
  final AzmSpendOptions? options;
  final bool loading;
  final String? error;

  /// Last successful fee discount applied (for withdrawal flow integration)
  final FeeDiscountResult? lastFeeDiscount;

  /// Last successful ad boost (for UI confirmation)
  final AdBoostResult? lastAdBoost;

  const AzmSpendState({
    this.options,
    this.loading = false,
    this.error,
    this.lastFeeDiscount,
    this.lastAdBoost,
  });

  AzmSpendState copyWith({
    AzmSpendOptions? options,
    bool? loading,
    String? error,
    FeeDiscountResult? lastFeeDiscount,
    AdBoostResult? lastAdBoost,
  }) {
    return AzmSpendState(
      options: options ?? this.options,
      loading: loading ?? this.loading,
      error: error,
      lastFeeDiscount: lastFeeDiscount ?? this.lastFeeDiscount,
      lastAdBoost: lastAdBoost ?? this.lastAdBoost,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AzmSpendNotifier extends StateNotifier<AzmSpendState> {
  AzmSpendNotifier() : super(const AzmSpendState());

  bool _primed = false;

  /// Load spend options (idempotent).
  Future<void> primeIfNeeded() async {
    if (_primed) return;
    _primed = true;
    await refresh();
  }

  /// Full refresh — re-fetch spend options from server.
  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);

    try {
      final options = await azmSpendService.getSpendOptions();
      state = AzmSpendState(options: options, loading: false);
    } catch (e) {
      debugPrint('[AzmSpendNotifier] refresh error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Apply a fee discount tier. Returns the result on success, null on failure.
  Future<FeeDiscountResult?> applyFeeDiscount(String tierId) async {
    try {
      final result = await azmSpendService.applyFeeDiscount(tierId);

      // Update local options with the new balance
      final currentOptions = state.options;
      if (currentOptions != null) {
        final updatedOptions = AzmSpendOptions(
          currentBalance: result.newAzmBalance,
          feeDiscounts: currentOptions.feeDiscounts.map((t) {
            return FeeDiscountTier(
              id: t.id,
              label: t.label,
              discount: t.discount,
              cost: t.cost,
              affordable: result.newAzmBalance >= t.cost,
            );
          }).toList(),
          adBoosts: currentOptions.adBoosts.map((o) {
            return AdBoostOption(
              id: o.id,
              label: o.label,
              cost: o.cost,
              affordable: result.newAzmBalance >= o.cost,
            );
          }).toList(),
        );
        state = state.copyWith(
          options: updatedOptions,
          lastFeeDiscount: result,
        );
      } else {
        state = state.copyWith(lastFeeDiscount: result);
      }

      return result;
    } catch (e) {
      debugPrint('[AzmSpendNotifier] applyFeeDiscount error: $e');
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Boost an ad. Returns the result on success, null on failure.
  Future<AdBoostResult?> boostAd(int adId, String boostId) async {
    try {
      final result = await azmSpendService.boostAd(adId, boostId);

      // Update local options with the new balance
      final currentOptions = state.options;
      if (currentOptions != null) {
        final updatedOptions = AzmSpendOptions(
          currentBalance: result.newAzmBalance,
          feeDiscounts: currentOptions.feeDiscounts.map((t) {
            return FeeDiscountTier(
              id: t.id,
              label: t.label,
              discount: t.discount,
              cost: t.cost,
              affordable: result.newAzmBalance >= t.cost,
            );
          }).toList(),
          adBoosts: currentOptions.adBoosts.map((o) {
            return AdBoostOption(
              id: o.id,
              label: o.label,
              cost: o.cost,
              affordable: result.newAzmBalance >= o.cost,
            );
          }).toList(),
        );
        state = state.copyWith(
          options: updatedOptions,
          lastAdBoost: result,
        );
      } else {
        state = state.copyWith(lastAdBoost: result);
      }

      return result;
    } catch (e) {
      debugPrint('[AzmSpendNotifier] boostAd error: $e');
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Called when a real-time `azm_spend` socket event arrives.
  /// Updates local balance state.
  void onRealtimeSpend({
    required double azmBalance,
    required double spent,
    required String source,
    required String reason,
  }) {
    final currentOptions = state.options;
    if (currentOptions != null) {
      final updatedOptions = AzmSpendOptions(
        currentBalance: azmBalance,
        feeDiscounts: currentOptions.feeDiscounts.map((t) {
          return FeeDiscountTier(
            id: t.id,
            label: t.label,
            discount: t.discount,
            cost: t.cost,
            affordable: azmBalance >= t.cost,
          );
        }).toList(),
        adBoosts: currentOptions.adBoosts.map((o) {
          return AdBoostOption(
            id: o.id,
            label: o.label,
            cost: o.cost,
            affordable: azmBalance >= o.cost,
          );
        }).toList(),
      );
      state = state.copyWith(options: updatedOptions);
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final azmSpendProvider =
    StateNotifierProvider<AzmSpendNotifier, AzmSpendState>((ref) {
  return AzmSpendNotifier();
});
