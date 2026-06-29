import 'package:flutter_riverpod/flutter_riverpod.dart';

class TransactionRecord {
  final String id;
  final String type; // IN, OUT, INTERNAL
  final double amountUsdc;
  final double feeUsdc;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  TransactionRecord({
    required this.id,
    required this.type,
    required this.amountUsdc,
    this.feeUsdc = 0,
    this.status = 'completed',
    required this.createdAt,
    this.metadata,
  });

  String get provider => metadata?['provider']?.toString() ?? '';
  double get amountGhs => (metadata?['amountGhs'] as num?)?.toDouble() ?? 0;
  double get rateAtInitiation => (metadata?['rateAtInitiation'] as num?)?.toDouble() ?? 0;

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    return TransactionRecord(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'IN',
      amountUsdc: (json['amountUsdc'] as num?)?.toDouble() ?? 0,
      feeUsdc: (json['feeUsdc'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'completed',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

class TransactionHistoryState {
  final List<TransactionRecord> items;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String filter;

  const TransactionHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.filter = 'ALL',
  });

  TransactionHistoryState copyWith({
    List<TransactionRecord>? items,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? filter,
  }) {
    return TransactionHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      filter: filter ?? this.filter,
    );
  }
}

class TransactionHistoryNotifier extends StateNotifier<TransactionHistoryState> {
  TransactionHistoryNotifier() : super(const TransactionHistoryState());

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    await Future.delayed(const Duration(milliseconds: 500));
    final mockItems = List.generate(15, (i) {
      final types = ['IN', 'OUT', 'INTERNAL'];
      final idx = state.items.length + i;
      return TransactionRecord(
        id: 'txn_${idx}_${DateTime.now().millisecondsSinceEpoch}',
        type: types[idx % 3],
        amountUsdc: (idx + 1) * 10.0,
        feeUsdc: 0.5,
        status: 'completed',
        createdAt: DateTime.now().subtract(Duration(hours: idx)),
        metadata: {
          'provider': 'vodafone',
          'amountGhs': (idx + 1) * 10.0 * 12.5,
          'rateAtInitiation': 12.5,
        },
      );
    });
    state = state.copyWith(
      items: [...state.items, ...mockItems],
      isLoading: false,
      hasMore: state.items.length < 100,
      page: state.page + 1,
    );
  }

  void setFilter(String filter) {
    if (filter == state.filter) return;
    state = const TransactionHistoryState();
    loadMore();
  }
}

final transactionHistoryProvider =
    StateNotifierProvider<TransactionHistoryNotifier, TransactionHistoryState>(
  (ref) => TransactionHistoryNotifier(),
);
