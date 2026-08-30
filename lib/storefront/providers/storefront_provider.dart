// =============================================================================
// Storefront Provider — Riverpod State Management
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/storefront_models.dart';
import '../services/storefront_service.dart';
import '../services/storefront_conflict_exception.dart';

final storefrontServiceProvider = Provider<StorefrontService>((ref) => StorefrontService());

final storefrontThemesProvider = FutureProvider<List<StorefrontTheme>>((ref) => ref.read(storefrontServiceProvider).listThemes());
final storefrontWidgetsProvider = FutureProvider<List<StorefrontWidget>>((ref) => ref.read(storefrontServiceProvider).listWidgets());
final storefrontTemplatesProvider = FutureProvider<List<StorefrontLayoutTemplate>>((ref) => ref.read(storefrontServiceProvider).listTemplates());

class DraftLayoutState {
  final StorefrontLayout? layout;
  final bool isLoading;
  final bool isSaving;
  final bool isPublishing;
  final String? error;
  final bool hasConflict;

  DraftLayoutState({this.layout, this.isLoading = false, this.isSaving = false, this.isPublishing = false, this.error, this.hasConflict = false});

  DraftLayoutState copyWith({StorefrontLayout? layout, bool? isLoading, bool? isSaving, bool? isPublishing, String? error, bool clearError = false, bool? hasConflict}) {
    return DraftLayoutState(
      layout: layout ?? this.layout,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isPublishing: isPublishing ?? this.isPublishing,
      error: clearError ? null : error ?? this.error,
      hasConflict: clearError ? false : hasConflict ?? this.hasConflict,
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
      final updated = await _service.saveDraft(layoutJson: layoutJson, themeId: themeId, expectedUpdatedAt: state.layout?.updatedAt?.toIso8601String());
      state = state.copyWith(layout: updated, isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString(), hasConflict: e is StorefrontConflictException);
      return false;
    }
  }

  Future<bool> publish() async {
    state = state.copyWith(isPublishing: true, clearError: true);
    try {
      final published = await _service.publish(expectedUpdatedAt: state.layout?.updatedAt?.toIso8601String());
      state = state.copyWith(layout: published, isPublishing: false);
      return true;
    } catch (e) {
      state = state.copyWith(isPublishing: false, error: e.toString(), hasConflict: e is StorefrontConflictException);
      return false;
    }
  }

  Future<void> applyTemplate(String templateId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final layout = await _service.applyTemplate(templateId, expectedUpdatedAt: state.layout?.updatedAt?.toIso8601String());
      state = state.copyWith(layout: layout, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString(), hasConflict: e is StorefrontConflictException);
    }
  }

  Future<void> revertToVersion(String versionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final layout = await _service.revertToVersion(versionId, expectedUpdatedAt: state.layout?.updatedAt?.toIso8601String());
      state = state.copyWith(layout: layout, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString(), hasConflict: e is StorefrontConflictException);
    }
  }

  void reset() => state = DraftLayoutState();
}

final draftLayoutProvider = StateNotifierProvider<DraftLayoutNotifier, DraftLayoutState>((ref) => DraftLayoutNotifier(ref.read(storefrontServiceProvider)));
final storefrontHistoryProvider = FutureProvider<List<StorefrontLayoutVersion>>((ref) => ref.read(storefrontServiceProvider).getHistory());
final storefrontEligibilityProvider = FutureProvider<StorefrontEligibility>((ref) => ref.read(storefrontServiceProvider).getEligibility());
final storefrontRenderProvider = FutureProvider.family<StorefrontRenderResponse?, String>((ref, bizId) => StorefrontService().renderStorefront(bizId));
final azmStakesProvider = FutureProvider<List<AzmStake>>((ref) => ref.read(storefrontServiceProvider).getStakes());
final azmTierProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.read(storefrontServiceProvider).getTierInfo());
final stakesProvider = FutureProvider<List<AzmStake>>((ref) => ref.read(storefrontServiceProvider).getStakes());
final eligibilityProvider = FutureProvider<StorefrontEligibility>((ref) => ref.read(storefrontServiceProvider).getEligibility());

final stakingProvider = StateNotifierProvider<StakingNotifier, AsyncValue<void>>((ref) => StakingNotifier(ref.read(storefrontServiceProvider)));

class StakingNotifier extends StateNotifier<AsyncValue<void>> {
  final StorefrontService _service;
  StakingNotifier(this._service) : super(const AsyncValue.data(null));
  Future<void> createStake(int amountAzm) async { state = const AsyncValue.loading(); try { await _service.createStake(amountAzm.toDouble()); state = const AsyncValue.data(null); } catch (e, st) { state = AsyncValue.error(e, st); rethrow; } }
  Future<void> requestUnstake(String stakeId) async { state = const AsyncValue.loading(); try { await _service.requestUnstake(stakeId); state = const AsyncValue.data(null); } catch (e, st) { state = AsyncValue.error(e, st); rethrow; } }
}

final storefrontDiscoveryProvider = FutureProvider.family<List<Map<String, dynamic>>, StorefrontDiscoveryQuery>((ref, query) => ref.read(storefrontServiceProvider).discoverStorefronts(query: query.search, category: query.category, limit: query.limit, offset: query.offset));

class StorefrontDiscoveryQuery {
  final String? search;
  final String? category;
  final int limit;
  final int offset;
  const StorefrontDiscoveryQuery({this.search, this.category, this.limit = 20, this.offset = 0});
  @override bool operator ==(Object other) => other is StorefrontDiscoveryQuery && other.search == search && other.category == category && other.limit == limit && other.offset == offset;
  @override int get hashCode => Object.hash(search, category, limit, offset);
}
