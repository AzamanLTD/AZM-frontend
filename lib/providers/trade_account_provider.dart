// lib/providers/trade_account_provider.dart
// =============================================================================
// AZAMAN V2 — TRADE ACCOUNT PROVIDER (Phase F2-FE)
//
// Riverpod state management for trade accounts. Handles:
//   - Fetching all accounts (with status filtering)
//   - Fetching only approved accounts (for ad creation)
//   - Adding new accounts
//   - Deleting accounts
//   - Optimistic UI updates
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/trade_account_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TradeAccountState {
  final List<TradeAccount> accounts;
  final List<TradeAccount> approvedAccounts;
  final bool isLoading;
  final bool isAdding;
  final String? error;

  const TradeAccountState({
    this.accounts = const [],
    this.approvedAccounts = const [],
    this.isLoading = false,
    this.isAdding = false,
    this.error,
  });

  TradeAccountState copyWith({
    List<TradeAccount>? accounts,
    List<TradeAccount>? approvedAccounts,
    bool? isLoading,
    bool? isAdding,
    String? error,
  }) {
    return TradeAccountState(
      accounts: accounts ?? this.accounts,
      approvedAccounts: approvedAccounts ?? this.approvedAccounts,
      isLoading: isLoading ?? this.isLoading,
      isAdding: isAdding ?? this.isAdding,
      error: error,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TradeAccountNotifier extends StateNotifier<TradeAccountState> {
  TradeAccountNotifier() : super(const TradeAccountState());

  bool _primed = false;

  /// Fetch all accounts if not already loaded. Safe to call multiple times.
  Future<void> primeIfNeeded() async {
    if (_primed) return;
    _primed = true;
    await refresh();
  }

  /// Force-refresh all accounts from the backend.
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final accounts = await TradeAccountService.getTradeAccounts();
      final approved = accounts.where((a) => a.isApproved).toList();
      state = state.copyWith(
        accounts: accounts,
        approvedAccounts: approved,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('TradeAccountProvider refresh error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Fetch only approved accounts (lightweight, for ad creation flow)
  Future<List<TradeAccount>> fetchApproved() async {
    try {
      final approved = await TradeAccountService.getApprovedAccounts();
      state = state.copyWith(approvedAccounts: approved);
      return approved;
    } catch (e) {
      debugPrint('TradeAccountProvider fetchApproved error: $e');
      return state.approvedAccounts;
    }
  }

  /// Add a new trade account. Returns the created account on success.
  Future<TradeAccount?> addAccount({
    required String methodType,
    required Map<String, dynamic> accountDetails,
    required String verificationScreenshot,
    String riskLevel = 'MEDIUM',
  }) async {
    state = state.copyWith(isAdding: true, error: null);
    try {
      final newAccount = await TradeAccountService.addTradeAccount(
        methodType: methodType,
        accountDetails: accountDetails,
        verificationScreenshot: verificationScreenshot,
        riskLevel: riskLevel,
      );
      // Optimistic: add to list immediately
      state = state.copyWith(
        accounts: [newAccount, ...state.accounts],
        isAdding: false,
      );
      return newAccount;
    } catch (e) {
      debugPrint('TradeAccountProvider addAccount error: $e');
      state = state.copyWith(isAdding: false, error: e.toString());
      return null;
    }
  }

  /// Delete a trade account by ID.
  Future<bool> deleteAccount(String id) async {
    try {
      await TradeAccountService.deleteTradeAccount(id);
      // Optimistic: remove from lists immediately
      state = state.copyWith(
        accounts: state.accounts.where((a) => a.id != id).toList(),
        approvedAccounts: state.approvedAccounts.where((a) => a.id != id).toList(),
      );
      return true;
    } catch (e) {
      debugPrint('TradeAccountProvider deleteAccount error: $e');
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final tradeAccountProvider =
    StateNotifierProvider<TradeAccountNotifier, TradeAccountState>(
  (ref) => TradeAccountNotifier(),
);
