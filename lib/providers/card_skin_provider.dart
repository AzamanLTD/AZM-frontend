// =============================================================================
// AZAMAN — CARD SKIN PROVIDER (2026-07-06)
//
// Riverpod state layer for the Azaman Store's card skin catalog: fetching
// the catalog (owned/equipped/affordable per skin), purchasing a skin with
// AZM, and equipping an owned skin. Consumed by AzamanStoreScreen.
//
// State refreshes:
//   - On screen mount (via .primeIfNeeded())
//   - Optimistically after a successful purchase/equip (server response is
//     the source of truth — we just fold it into local state, no re-fetch
//     needed for the common case).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/azm_spend_service.dart';

class CardSkinState {
  final CardSkinCatalog? catalog;
  final bool loading;
  // Tracks an in-flight purchase/equip per-skin so the UI can show a
  // per-tile spinner instead of blocking the whole screen.
  final String? pendingSkinId;
  final String? error;

  const CardSkinState({
    this.catalog,
    this.loading = false,
    this.pendingSkinId,
    this.error,
  });

  CardSkinState copyWith({
    CardSkinCatalog? catalog,
    bool? loading,
    String? pendingSkinId,
    bool clearPending = false,
    String? error,
    bool clearError = false,
  }) {
    return CardSkinState(
      catalog: catalog ?? this.catalog,
      loading: loading ?? this.loading,
      pendingSkinId: clearPending ? null : (pendingSkinId ?? this.pendingSkinId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CardSkinNotifier extends StateNotifier<CardSkinState> {
  CardSkinNotifier() : super(const CardSkinState());

  bool _primed = false;

  Future<void> primeIfNeeded() async {
    if (_primed) return;
    _primed = true;
    await refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final catalog = await azmSpendService.getCardSkinCatalog();
      state = CardSkinState(catalog: catalog, loading: false);
    } catch (e) {
      debugPrint('[CardSkinNotifier] refresh error: $e');
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Purchase a skin. Returns true on success (including the idempotent
  /// "already owned" no-op), false on failure (state.error is set).
  Future<bool> purchase(String skinId) async {
    state = state.copyWith(pendingSkinId: skinId, clearError: true);
    try {
      final result = await azmSpendService.purchaseCardSkin(skinId);
      _foldOwnershipUpdate(ownedSkinIds: result.ownedCardSkins, newBalance: result.newBalance);
      state = state.copyWith(clearPending: true);
      return true;
    } catch (e) {
      debugPrint('[CardSkinNotifier] purchase error: $e');
      state = state.copyWith(clearPending: true, error: e.toString());
      return false;
    }
  }

  /// Equip an owned skin (or 'classic'). Returns true on success.
  Future<bool> equip(String skinId) async {
    state = state.copyWith(pendingSkinId: skinId, clearError: true);
    try {
      final equipped = await azmSpendService.equipCardSkin(skinId);
      final current = state.catalog;
      if (current != null) {
        state = state.copyWith(
          catalog: CardSkinCatalog(
            skins: current.skins,
            equippedCardSkin: equipped,
            azmBalance: current.azmBalance,
          ),
          clearPending: true,
        );
      } else {
        state = state.copyWith(clearPending: true);
      }
      return true;
    } catch (e) {
      debugPrint('[CardSkinNotifier] equip error: $e');
      state = state.copyWith(clearPending: true, error: e.toString());
      return false;
    }
  }

  void _foldOwnershipUpdate({required List<String> ownedSkinIds, required double newBalance}) {
    final current = state.catalog;
    if (current == null) return;
    final updatedSkins = current.skins.map((s) {
      final owned = s.owned || ownedSkinIds.contains(s.id);
      return CardSkinOption(
        id: s.id,
        label: s.label,
        cost: s.cost,
        owned: owned,
        affordable: owned || newBalance >= s.cost,
      );
    }).toList();
    state = state.copyWith(
      catalog: CardSkinCatalog(
        skins: updatedSkins,
        equippedCardSkin: current.equippedCardSkin,
        azmBalance: newBalance,
      ),
    );
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final cardSkinProvider = StateNotifierProvider<CardSkinNotifier, CardSkinState>((ref) {
  return CardSkinNotifier();
});
