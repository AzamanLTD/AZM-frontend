import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/api_client.dart';

/// Categorises a raw backend [TransactionType] enum into one of three
/// UI-facing buckets: `DEPOSIT`, `WITHDRAWAL`, or `TRANSFER`.
///
//  'in' / 'deposit'   → Deposit   (green / arrow-down)
//  'out' / 'withdrawal' → Withdrawal (red / arrow-up)
//  'internal' / 'transfer' → Transfer  (blue / swap icon)
String _categorize(String rawType) {
  const deposits = <String>{
    'DEPOSIT_FIAT', 'DEPOSIT_CRYPTO', 'SUSU_PAYOUT', 'VAULT_RELEASE',
    'AZM_REWARD', 'SUSU_REFUND', 'SUSU_PROFIT', 'TICKET_ESCROW_RELEASE',
    'TICKET_ESCROW_REFUND', 'BUSINESS_INVOICE_RECEIPT', 'PAYROLL_DISBURSEMENT',
  };
  const withdrawals = <String>{
    'WITHDRAWAL_FIAT', 'WITHDRAWAL_CRYPTO', 'SUSU_CONTRIBUTION', 'VAULT_DEPOSIT',
    'SUSU_SEIZURE', 'TICKET_ESCROW_FUND', 'TICKET_ESCROW_FEE',
    'BUSINESS_INVOICE_PAYMENT', 'EWA_WITHDRAWAL',
  };
  const transfers = <String>{
    'INTERNAL_TRANSFER', 'SMART_ROUTE_RUN', 'P2P_TRADE',
  };

  final upper = rawType.toUpperCase();
  if (deposits.contains(upper)) return 'DEPOSIT';
  if (withdrawals.contains(upper)) return 'WITHDRAWAL';
  if (transfers.contains(upper)) return 'TRANSFER';

  // Fallback heuristics for any future enum values.
  if (upper.contains('DEPOSIT') ||
      upper.contains('PAYOUT') ||
      upper.contains('REWARD') ||
      upper.contains('RELEASE') ||
      upper.contains('REFUND') ||
      upper.contains('RECEIPT') ||
      upper.contains('DISBURSEMENT')) {
    return 'DEPOSIT';
  }
  if (upper.contains('WITHDRAWAL') ||
      upper.contains('CONTRIBUTION') ||
      upper.contains('SEIZURE') ||
      upper.contains('FUND') ||
      upper.contains('FEE') ||
      upper.contains('PAYMENT')) {
    return 'WITHDRAWAL';
  }
  if (upper.contains('TRANSFER') ||
      upper.contains('ROUTE') ||
      upper.contains('P2P')) {
    return 'TRANSFER';
  }
  return 'DEPOSIT';
}

class TransactionRecord {
  final String id;
  final String rawType; // Backend enum: DEPOSIT_FIAT, WITHDRAWAL_CRYPTO, INTERNAL_TRANSFER, etc.
  final double amountUsdc;
  final double feeUsdc;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;
  final String? txHash;
  final String? providerRef;

  TransactionRecord({
    required this.id,
    required this.rawType,
    required this.amountUsdc,
    this.feeUsdc = 0,
    this.status = 'COMPLETED',
    required this.createdAt,
    this.metadata,
    this.txHash,
    this.providerRef,
  });

  /// UI-facing category: `DEPOSIT`, `WITHDRAWAL`, or `TRANSFER`.
  String get category => _categorize(rawType);

  String get provider => metadata?['provider']?.toString() ?? '';
  double get amountGhs => (metadata?['amountGhs'] as num?)?.toDouble() ?? 0;
  double get rateAtInitiation =>
      (metadata?['rateAtInitiation'] as num?)?.toDouble() ?? 0;

  /// Counterparty name or AZM-ID if available in metadata.
  String get counterparty =>
      metadata?['counterparty']?.toString() ??
      metadata?['recipientName']?.toString() ??
      metadata?['senderName']?.toString() ??
      metadata?['recipientAzamId']?.toString() ??
      '';

  /// Human-readable description derived from metadata or type.
  String get description =>
      metadata?['description']?.toString() ?? '';

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: json['id']?.toString() ?? '',
      rawType: json['type']?.toString() ?? 'DEPOSIT_FIAT',
      amountUsdc: (json['amountUsdc'] as num?)?.toDouble() ?? 0,
      feeUsdc: (json['feeUsdc'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'COMPLETED',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata']
          : (json['metadata'] is Map
              ? Map<String, dynamic>.from(json['metadata'])
              : null),
      txHash: json['txHash']?.toString(),
      providerRef: json['providerRef']?.toString(),
    );
  }
}

class TransactionHistoryState {
  final List<TransactionRecord> items;
  final bool isLoading;
  final bool hasMore;
  final String? nextCursor;
  final String filter;
  final String? error;

  const TransactionHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.nextCursor,
    this.filter = 'ALL',
    this.error,
  });

  TransactionHistoryState copyWith({
    List<TransactionRecord>? items,
    bool? isLoading,
    bool? hasMore,
    String? nextCursor,
    String? filter,
    String? error,
    bool clearError = false,
  }) {
    return TransactionHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor,
      filter: filter ?? this.filter,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class TransactionHistoryNotifier extends StateNotifier<TransactionHistoryState> {
  TransactionHistoryNotifier() : super(const TransactionHistoryState());

  /// Fetch the next page of transactions from the real backend API.
  /// Uses cursor-based pagination matching GET /api/finance/transactions.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Build query string from filter + cursor.
      final params = <String>[];
      if (state.filter != 'ALL') {
        params.add('filter=${state.filter}');
      }
      if (state.nextCursor != null && state.nextCursor!.isNotEmpty) {
        params.add('cursor=${state.nextCursor}');
      }
      final query = params.isEmpty ? '' : '?${params.join('&')}';

      final response = await apiClient.get('/finance/transactions$query');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List txnsJson = body['transactions'] ?? [];
        final hasMore = body['hasMore'] ?? false;
        final nextCursor = body['nextCursor']?.toString();

        final newItems = txnsJson
            .map<TransactionRecord>((json) => TransactionRecord.fromJson(
                  json is Map<String, dynamic>
                      ? json
                      : Map<String, dynamic>.from(json),
                ))
            .toList();

        state = state.copyWith(
          items: [...state.items, ...newItems],
          isLoading: false,
          hasMore: hasMore,
          nextCursor: nextCursor,
        );
        debugPrint(
            '[TransactionHistory] Loaded ${newItems.length} txns, hasMore=$hasMore');
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load transactions',
        );
      }
    } catch (e) {
      debugPrint('[TransactionHistory] Fetch error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load transactions. Pull to retry.',
      );
    }
  }

  /// Refresh from scratch (clears items + cursor, then fetches).
  Future<void> refresh() async {
    state = TransactionHistoryState(filter: state.filter);
    await loadMore();
  }

  void setFilter(String filter) {
    if (filter == state.filter) return;
    state = TransactionHistoryState(filter: filter);
    loadMore();
  }
}

final transactionHistoryProvider =
    StateNotifierProvider<TransactionHistoryNotifier, TransactionHistoryState>(
  (ref) => TransactionHistoryNotifier(),
);
