// =============================================================================
// Storefront Provider — Riverpod State Management
//
// Providers for storefront themes, widgets, templates, draft/published layouts,
// eligibility, AZM staking, and the public render endpoint.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storefront_models.dart';
import '../services/storefront_service.dart';

// ── Service singleton ────────────────────────────────────────────────────────

final storefrontServiceProvider = Provider<StorefrontService>((ref) {
  return StorefrontService();
});

// ── Themes ───────────────────────────────────────────────────────────────────

final storefrontThemesProvider = FutureProvider<List<StorefrontTheme>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.listThemes();
});

// ── Widgets ──────────────────────────────────────────────────────────────────

final storefrontWidgetsProvider = FutureProvider<List<StorefrontWidget>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.listWidgets();
});

// ── Templates ────────────────────────────────────────────────────────────────

final storefrontTemplatesProvider = FutureProvider<List<StorefrontLayoutTemplate>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.listTemplates();
});

// ── Draft Layout ─────────────────────────────────────────────────────────────

class DraftLayoutState {
  final StorefrontLayout? layout;
  final bool isLoading;
  final bool isSaving;
  final bool isPublishing;
  final String? error;

  DraftLayoutState({
    this.layout,
    this.isLoading = false,
    this.isSaving = false,
    this.isPublishing = false,
    this.error,
  });

  DraftLayoutState copyWith({
    StorefrontLayout? layout,
    bool? isLoading,
    bool? isSaving,
    bool? isPublishing,
    String? error,
    bool clearError = false,
  }) {
    return DraftLayoutState(
      layout: layout ?? this.layout,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isPublishing: isPublishing ?? this.isPublishing,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class DraftLayoutNotifier extends StateNotifier<DraftLayoutState> {
  final StorefrontService _service;

  DraftLayoutNotifier(this._service) : super(DraftLayoutState());

  Future<void> loadDraft() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final layout = await _service.getDraft();
      state = state.copyWith(layout: layout, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> saveDraft({required LayoutJson layoutJson, required String themeId}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _service.saveDraft(
        layoutJson: layoutJson,
        themeId: themeId,
        expectedUpdatedAt: state.layout?.updatedAt?.toIso8601String(),
      );
      state = state.copyWith(layout: updated, isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return false;
    }
  }

  Future<bool> publish() async {
    state = state.copyWith(isPublishing: true, clearError: true);
    try {
      await _service.publish();
      state = state.copyWith(isPublishing: false);
      return true;
    } catch (e) {
      state = state.copyWith(isPublishing: false, error: e.toString());
      return false;
    }
  }

  Future<void> applyTemplate(String templateId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final layout = await _service.applyTemplate(templateId);
      state = state.copyWith(layout: layout, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> revertToVersion(String versionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final layout = await _service.revertToVersion(versionId);
      state = state.copyWith(layout: layout, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = DraftLayoutState();
  }
}

final draftLayoutProvider =
    StateNotifierProvider<DraftLayoutNotifier, DraftLayoutState>((ref) {
  return DraftLayoutNotifier(ref.read(storefrontServiceProvider));
});

// ── Version History ──────────────────────────────────────────────────────────

final storefrontHistoryProvider =
    FutureProvider<List<StorefrontLayoutVersion>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getHistory();
});

// ── Eligibility ──────────────────────────────────────────────────────────────

final storefrontEligibilityProvider =
    FutureProvider<StorefrontEligibility>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getEligibility();
});

// ── Public Render ─────────────────────────────────────────────────────────────

final storefrontRenderProvider =
    FutureProvider.family<StorefrontRenderResponse?, String>((ref, bizId) async {
  final service = StorefrontService();
  return service.renderStorefront(bizId);
});

// ── AZM Stakes ────────────────────────────────────────────────────────────────

final azmStakesProvider = FutureProvider<List<AzmStake>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getStakes();
});

final azmTierProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getTierInfo();
});

// ── Staking Providers ────────────────────────────────────────────────────────

/// User's active stakes
final stakesProvider = FutureProvider<List<AzmStake>>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getStakes();
});

/// User's Nitro eligibility (staked balance, tier, disabled status)
final eligibilityProvider = FutureProvider<StorefrontEligibility>((ref) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getEligibility();
});

/// Staking actions (create stake, request unstake)
final stakingProvider = StateNotifierProvider<StakingNotifier, AsyncValue<void>>((ref) {
  return StakingNotifier(ref.read(storefrontServiceProvider));
});

class StakingNotifier extends StateNotifier<AsyncValue<void>> {
  final StorefrontService _service;
  StakingNotifier(this._service) : super(const AsyncValue.data(null));

  Future<void> createStake(int amountAzm) async {
    state = const AsyncValue.loading();
    try {
      await _service.createStake(amountAzm.toDouble());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> requestUnstake(String stakeId) async {
    state = const AsyncValue.loading();
    try {
      await _service.requestUnstake(stakeId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

// ── Storefront Discovery (Phase 2) ─────────────────────────────────────────────

/// Discover businesses with published storefronts.
/// Supports search query, category filter, and pagination via refresh family.
final storefrontDiscoveryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, StorefrontDiscoveryQuery>((ref, query) async {
  final service = ref.read(storefrontServiceProvider);
  return service.discoverStorefronts(
    query: query.search,
    category: query.category,
    limit: query.limit,
    offset: query.offset,
  );
});

class StorefrontDiscoveryQuery {
  final String? search;
  final String? category;
  final int limit;
  final int offset;

  const StorefrontDiscoveryQuery({
    this.search,
    this.category,
    this.limit = 20,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is StorefrontDiscoveryQuery &&
      other.search == search &&
      other.category == category &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(search, category, offset);
}

/// Public product listing for a business's storefront (Phase 4 — direct ordering).
final storefrontProductsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, businessProfileId) async {
  final service = ref.read(storefrontServiceProvider);
  return service.getStorefrontProducts(businessProfileId);
});
