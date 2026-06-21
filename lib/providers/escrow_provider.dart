// =============================================================================
// ESCROW PROVIDER — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Riverpod state for a single ticket's Smart Escrow. Mirrors the
// `TicketWorkspaceNotifier` shape: one family notifier keyed by ticketId,
// granular busy flags so the panel can show per-action spinners, and an
// `onRealtimeUpdate` bridge the workspace socket listener calls when an
// `escrow_*` event for this ticket arrives.
//
// Mutations rethrow so the calling widget can surface a SnackBar; on the happy
// path they fire the matching haptic and refresh local state.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/escrow_models.dart';
import 'package:azaman/services/escrow_service.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class EscrowState {
  final SmartEscrow? escrow;
  final bool isLoading;
  final bool isFunding;
  final bool isSatisfying;
  final bool isDisputing;
  final String? error;

  const EscrowState({
    this.escrow,
    this.isLoading = false,
    this.isFunding = false,
    this.isSatisfying = false,
    this.isDisputing = false,
    this.error,
  });

  EscrowState copyWith({
    SmartEscrow? escrow,
    bool? isLoading,
    bool? isFunding,
    bool? isSatisfying,
    bool? isDisputing,
    String? error,
    bool clearError = false,
  }) {
    return EscrowState(
      escrow: escrow ?? this.escrow,
      isLoading: isLoading ?? this.isLoading,
      isFunding: isFunding ?? this.isFunding,
      isSatisfying: isSatisfying ?? this.isSatisfying,
      isDisputing: isDisputing ?? this.isDisputing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class EscrowNotifier extends StateNotifier<EscrowState> {
  final String _ticketId;
  final EscrowService _service;

  EscrowNotifier(this._ticketId, this._service) : super(const EscrowState());

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final escrow = await _service.getEscrowForTicket(_ticketId);
      state = state.copyWith(escrow: escrow, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> fund() async {
    final id = state.escrow?.id;
    if (id == null) return;
    state = state.copyWith(isFunding: true, clearError: true);
    try {
      final updated = await _service.fundEscrow(id);
      state = state.copyWith(escrow: updated, isFunding: false);
      AzamanHaptics.commit();
    } catch (e) {
      state = state.copyWith(isFunding: false, error: e.toString());
      rethrow;
    }
  }

  /// Marks the caller satisfied. Returns whether the escrow is now fully
  /// settled (both parties satisfied).
  Future<bool> markSatisfied() async {
    final id = state.escrow?.id;
    if (id == null) return false;
    state = state.copyWith(isSatisfying: true, clearError: true);
    try {
      final result = await _service.markSatisfied(id);
      state = state.copyWith(escrow: result.escrow, isSatisfying: false);
      AzamanHaptics.commit();
      return result.settled;
    } catch (e) {
      state = state.copyWith(isSatisfying: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> raiseDispute(String reason, List<String> evidenceUrls) async {
    final id = state.escrow?.id;
    if (id == null) return;
    state = state.copyWith(isDisputing: true, clearError: true);
    try {
      final updated = await _service.raiseDispute(
        escrowId: id,
        reason: reason,
        evidenceUrls: evidenceUrls,
      );
      state = state.copyWith(escrow: updated, isDisputing: false);
      AzamanHaptics.warn();
    } catch (e) {
      state = state.copyWith(isDisputing: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> updateTerms(String terms) async {
    final id = state.escrow?.id;
    if (id == null) return;
    try {
      final updated = await _service.updateTerms(id, terms);
      state = state.copyWith(escrow: updated);
      AzamanHaptics.commit();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> cancel() async {
    final id = state.escrow?.id;
    if (id == null) return;
    try {
      await _service.cancelEscrow(id);
      AzamanHaptics.warn();
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Socket bridge — any `escrow_*` event for this ticket triggers a reload so
  /// the panel reflects the authoritative server state.
  void onRealtimeUpdate(Map<String, dynamic> event, String eventName) {
    load();
  }
}

final escrowProvider =
    StateNotifierProvider.family<EscrowNotifier, EscrowState, String>(
  (ref, ticketId) => EscrowNotifier(ticketId, EscrowService()),
);
