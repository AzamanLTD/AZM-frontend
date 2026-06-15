// =============================================================================
// AZAMAN — HOME SUMMARY SERVICE  (Phase G)
//
// Aggregates the data the home screen renders below the fold:
//
//   * Live oracle rates           — GET /api/oracle/rates
//   * Active trades (count + 3)   — GET /api/trades/history?status filter
//   * Pending withdrawals (<=3)   — GET /api/wallet/history (status PENDING)
//   * Pending friend requests     — GET /api/friends/requests
//   * Unread notifications        — GET /api/notifications/unread-count
//
// Five concurrent fetches via Future.wait so the home loads in ~1 round-trip
// even on flaky data. Each request is wrapped so a single failure doesn't
// torch the whole snapshot — the home shows partial data with `—` placeholders
// for whichever bucket failed.
//
// Returns a `HomeSummary` value object consumed by `homeSummaryProvider` and
// rendered by `TodayWidget` / `LiveMarketSection`.
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:azaman/services/api_client.dart';

// ── Sub-models ──────────────────────────────────────────────────────────────

class OracleRates {
  final double usdToGhs;
  final double retailRate;
  final double corporateRate;
  final String source;
  final DateTime? lastSync;

  const OracleRates({
    required this.usdToGhs,
    required this.retailRate,
    required this.corporateRate,
    required this.source,
    required this.lastSync,
  });

  static const empty = OracleRates(
    usdToGhs: 0,
    retailRate: 0,
    corporateRate: 0,
    source: 'UNAVAILABLE',
    lastSync: null,
  );

  bool get isAvailable => usdToGhs > 0;
}

class TradeSummary {
  final String id;
  final String status;
  final double amountGhs;
  final double amountUsdc;
  final DateTime? createdAt;
  final bool iAmVendor;

  const TradeSummary({
    required this.id,
    required this.status,
    required this.amountGhs,
    required this.amountUsdc,
    required this.createdAt,
    required this.iAmVendor,
  });
}

class WithdrawalSummary {
  final String id;
  final String status;
  final double amount;
  final String payoutMethod;
  final String? network;
  final DateTime? createdAt;

  const WithdrawalSummary({
    required this.id,
    required this.status,
    required this.amount,
    required this.payoutMethod,
    required this.network,
    required this.createdAt,
  });
}

class TransactionSummary {
  final String id;
  final String title;
  final double amount;
  final bool isCredit;
  final String status;
  final String symbol;
  final DateTime? createdAt;

  const TransactionSummary({
    required this.id,
    required this.title,
    required this.amount,
    required this.isCredit,
    required this.status,
    required this.symbol,
    required this.createdAt,
  });
}

class FriendRequestSummary {
  final String id;
  final String requesterUsername;
  final String? requesterAvatarUrl;
  final DateTime? createdAt;

  const FriendRequestSummary({
    required this.id,
    required this.requesterUsername,
    required this.requesterAvatarUrl,
    required this.createdAt,
  });
}

// ── Snapshot value object ──────────────────────────────────────────────────

@immutable
class HomeSummary {
  final OracleRates rates;

  /// Trades with status indicating the user has live work to do
  /// (PENDING, PENDING_PAYMENT, PAID, DISPUTED).
  final List<TradeSummary> activeTrades;
  final int activeTradesCount;

  final List<WithdrawalSummary> pendingWithdrawals;
  final int pendingWithdrawalsCount;

  /// Most-recent wallet movements (any status) for the home "Activity"
  /// section. Sourced from the same /wallet/history call as
  /// `pendingWithdrawals` so it costs no extra round-trip.
  final List<TransactionSummary> recentTransactions;

  final List<FriendRequestSummary> friendRequests;
  final int friendRequestsCount;

  final int unreadNotifications;

  /// Per-section error messages — null when that section loaded cleanly.
  /// The home screen surfaces `—` placeholders rather than blocking the
  /// whole render when one section fails.
  final String? ratesError;
  final String? tradesError;
  final String? withdrawalsError;
  final String? transactionsError;
  final String? friendsError;
  final String? notificationsError;

  /// True while *any* section is still in-flight on a refresh. The home
  /// screen uses this to disable the refresh button and gate the spinner.
  final bool loading;

  const HomeSummary({
    required this.rates,
    required this.activeTrades,
    required this.activeTradesCount,
    required this.pendingWithdrawals,
    required this.pendingWithdrawalsCount,
    this.recentTransactions = const [],
    required this.friendRequests,
    required this.friendRequestsCount,
    required this.unreadNotifications,
    this.ratesError,
    this.tradesError,
    this.withdrawalsError,
    this.transactionsError,
    this.friendsError,
    this.notificationsError,
    this.loading = false,
  });

  /// Cold start — every counter is zero, no errors, not yet loading.
  static const empty = HomeSummary(
    rates: OracleRates.empty,
    activeTrades: [],
    activeTradesCount: 0,
    pendingWithdrawals: [],
    pendingWithdrawalsCount: 0,
    friendRequests: [],
    friendRequestsCount: 0,
    unreadNotifications: 0,
  );

  HomeSummary copyWith({bool? loading}) => HomeSummary(
        rates: rates,
        activeTrades: activeTrades,
        activeTradesCount: activeTradesCount,
        pendingWithdrawals: pendingWithdrawals,
        pendingWithdrawalsCount: pendingWithdrawalsCount,
        recentTransactions: recentTransactions,
        friendRequests: friendRequests,
        friendRequestsCount: friendRequestsCount,
        unreadNotifications: unreadNotifications,
        ratesError: ratesError,
        tradesError: tradesError,
        withdrawalsError: withdrawalsError,
        transactionsError: transactionsError,
        friendsError: friendsError,
        notificationsError: notificationsError,
        loading: loading ?? this.loading,
      );
}

// ── Service ────────────────────────────────────────────────────────────────

/// Active-trade statuses we surface as "you have live work" on the home screen.
/// COMPLETED / CANCELLED / AUTO_CANCELLED are explicitly excluded.
///
/// Source of truth: `azaman-backend-main/prisma/schema.prisma::TradeStatus`.
/// Phase H review pass: was previously listing `AWAITING_RELEASE` (not in
/// the enum) and missing `PENDING` (the freshest status — invisible until
/// the trade transitioned).
const _activeStatuses = {
  'PENDING',
  'PENDING_PAYMENT',
  'PAID',
  'DISPUTED',
};

class HomeSummaryService {
  /// Fetch all five sections in parallel. Per-section failures degrade
  /// gracefully into the corresponding `*Error` field of the snapshot.
  Future<HomeSummary> fetch({String? currentUserId}) async {
    final results = await Future.wait<_Section>([
      _fetchRates(),
      _fetchTrades(currentUserId: currentUserId),
      _fetchWithdrawals(),
      _fetchFriendRequests(),
      _fetchUnreadCount(),
    ]);

    return HomeSummary(
      rates: results[0].rates ?? OracleRates.empty,
      ratesError: results[0].error,
      activeTrades: results[1].trades ?? const [],
      activeTradesCount: results[1].tradeCount ?? 0,
      tradesError: results[1].error,
      pendingWithdrawals: results[2].withdrawals ?? const [],
      pendingWithdrawalsCount: results[2].withdrawalCount ?? 0,
      withdrawalsError: results[2].error,
      recentTransactions: results[2].transactions ?? const [],
      transactionsError: results[2].error,
      friendRequests: results[3].friendRequests ?? const [],
      friendRequestsCount: results[3].friendRequestCount ?? 0,
      friendsError: results[3].error,
      unreadNotifications: results[4].unreadCount ?? 0,
      notificationsError: results[4].error,
    );
  }

  // ── Per-section fetchers ─────────────────────────────────────────────────

  Future<_Section> _fetchRates() async {
    try {
      final res = await apiClient.get('/oracle/rates', requireAuth: false);
      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic> || raw['success'] != true) {
        return const _Section(error: 'Rates unavailable.');
      }
      final data = raw['data'];
      if (data is! Map<String, dynamic>) {
        return const _Section(error: 'Rates payload malformed.');
      }
      return _Section(
        rates: OracleRates(
          usdToGhs: _asDouble(data['liveUsdToGhs']),
          retailRate: _asDouble(data['liveRetailRate']),
          corporateRate: _asDouble(data['liveCorporateRate']),
          source: data['rateSource']?.toString() ?? 'UNKNOWN',
          lastSync: _asDate(data['lastSync']),
        ),
      );
    } catch (e) {
      return _Section(error: _humanise(e));
    }
  }

  Future<_Section> _fetchTrades({String? currentUserId}) async {
    try {
      final res = await apiClient.get('/trades/history');
      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic> || raw['success'] != true) {
        return const _Section(error: 'Trades unavailable.');
      }
      final list = (raw['history'] as List?) ?? const [];
      final active = list
          .whereType<Map<String, dynamic>>()
          .where((t) => _activeStatuses
              .contains(t['status']?.toString().toUpperCase()))
          .toList();

      final mapped = active.map((t) {
        final iAmVendor = currentUserId != null &&
            t['vendorId']?.toString() == currentUserId;
        // Phase H review pass: the Prisma `Trade` model has no
        // `amountGhs` / `amountUsdc` columns. The actual fields are
        // `amountFiat` (with `currency` for the unit, defaulting to 'GHS')
        // and `amountCrypto` (with `crypto` for the symbol, typically USDT).
        return TradeSummary(
          id: t['id']?.toString() ?? '',
          status: t['status']?.toString() ?? 'UNKNOWN',
          amountGhs: _asDouble(t['amountFiat']),
          amountUsdc: _asDouble(t['amountCrypto']),
          createdAt: _asDate(t['createdAt']),
          iAmVendor: iAmVendor,
        );
      }).toList();

      return _Section(
        trades: mapped.take(3).toList(growable: false),
        tradeCount: mapped.length,
      );
    } catch (e) {
      return _Section(error: _humanise(e));
    }
  }

  Future<_Section> _fetchWithdrawals() async {
    try {
      final res = await apiClient.get('/wallet/history');
      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic> || raw['success'] != true) {
        return const _Section(error: 'Withdrawals unavailable.');
      }
      final list =
          (raw['history'] as List? ?? raw['withdrawals'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();

      final pending = list
          .where((w) =>
              (w['status']?.toString().toUpperCase() ?? '') == 'PENDING')
          .map((w) => WithdrawalSummary(
                id: w['id']?.toString() ?? '',
                status: w['status']?.toString() ?? 'UNKNOWN',
                amount: _asDouble(w['amount']),
                // Phase H review pass: the Prisma `Withdrawal` model has
                // no `currency` column. Use `payoutMethod` (defaults to
                // 'BINANCE_ID' on rows that pre-date the network split)
                // and the optional `network` for display.
                payoutMethod: w['payoutMethod']?.toString() ?? 'UNKNOWN',
                network: w['network']?.toString(),
                createdAt: _asDate(w['createdAt']),
              ))
          .toList();

      final recent = list
          .map(_txFromJson)
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));

      return _Section(
        withdrawals: pending.take(3).toList(growable: false),
        withdrawalCount: pending.length,
        transactions: recent.take(4).toList(growable: false),
      );
    } catch (e) {
      return _Section(error: _humanise(e));
    }
  }

  static const _creditHints = {
    'DEPOSIT', 'CREDIT', 'RECEIVE', 'RECEIVED', 'REFUND', 'TOPUP', 'TOP_UP',
    'FUND', 'INCOMING', 'REWARD', 'CASHBACK', 'RELEASE',
  };
  static const _debitHints = {
    'WITHDRAW', 'WITHDRAWAL', 'DEBIT', 'SEND', 'SENT', 'PAYOUT', 'FEE',
    'PURCHASE', 'OUTGOING', 'TRANSFER_OUT', 'SPEND',
  };

  TransactionSummary _txFromJson(Map<String, dynamic> w) {
    final type = (w['type'] ??
            w['transactionType'] ??
            w['category'] ??
            w['kind'] ??
            '')
        .toString()
        .toUpperCase();
    final direction =
        (w['direction'] ?? w['flow'] ?? '').toString().toUpperCase();
    final method = (w['payoutMethod'] ?? w['network'] ?? '')
        .toString()
        .replaceAll('_', ' ')
        .trim();

    bool isCredit;
    if (_creditHints.any(type.contains) || direction.contains('IN')) {
      isCredit = true;
    } else if (_debitHints.any(type.contains) || direction.contains('OUT')) {
      isCredit = false;
    } else {
      isCredit = false;
    }

    String title;
    if (type.isNotEmpty) {
      final pretty = type
          .replaceAll('_', ' ')
          .toLowerCase()
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
          .join(' ');
      title = method.isNotEmpty ? '$pretty · $method' : pretty;
    } else if (method.isNotEmpty) {
      title = method;
    } else {
      title = isCredit ? 'Money in' : 'Money out';
    }

    return TransactionSummary(
      id: w['id']?.toString() ?? '',
      title: title,
      amount: _asDouble(w['amount']).abs(),
      isCredit: isCredit,
      status: (w['status']?.toString() ?? 'UNKNOWN').toUpperCase(),
      symbol: (w['currency'] ?? w['crypto'] ?? 'USDC').toString().toUpperCase(),
      createdAt: _asDate(w['createdAt']),
    );
  }

  Future<_Section> _fetchFriendRequests() async {
    try {
      final res = await apiClient.get('/friends/requests?page=1&limit=20');
      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic> || raw['success'] != true) {
        return const _Section(error: 'Requests unavailable.');
      }
      final list = (raw['requests'] as List?) ?? const [];
      final mapped = list
          .whereType<Map<String, dynamic>>()
          .map((r) {
            final requester =
                r['requester'] is Map<String, dynamic> ? r['requester'] : null;
            return FriendRequestSummary(
              id: r['id']?.toString() ?? '',
              requesterUsername:
                  requester?['username']?.toString() ?? 'unknown',
              requesterAvatarUrl: requester?['profilePictureUrl']?.toString(),
              createdAt: _asDate(r['createdAt']),
            );
          })
          .toList();

      // The endpoint also returns a definitive `total` — prefer it for the
      // counter when present; fall back to the in-page length.
      final total = (raw['total'] as num?)?.toInt() ?? mapped.length;

      return _Section(
        friendRequests: mapped.take(3).toList(growable: false),
        friendRequestCount: total,
      );
    } catch (e) {
      return _Section(error: _humanise(e));
    }
  }

  Future<_Section> _fetchUnreadCount() async {
    try {
      final res = await apiClient.get('/notifications/unread-count');
      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic> || raw['success'] != true) {
        return const _Section(error: 'Unread count unavailable.');
      }
      return _Section(unreadCount: (raw['count'] as num?)?.toInt() ?? 0);
    } catch (e) {
      return _Section(error: _humanise(e));
    }
  }
}

// ── Internal: per-section result envelope ──────────────────────────────────

class _Section {
  final OracleRates? rates;
  final List<TradeSummary>? trades;
  final int? tradeCount;
  final List<WithdrawalSummary>? withdrawals;
  final int? withdrawalCount;
  final List<TransactionSummary>? transactions;
  final List<FriendRequestSummary>? friendRequests;
  final int? friendRequestCount;
  final int? unreadCount;
  final String? error;

  const _Section({
    this.rates,
    this.trades,
    this.tradeCount,
    this.withdrawals,
    this.withdrawalCount,
    this.transactions,
    this.friendRequests,
    this.friendRequestCount,
    this.unreadCount,
    this.error,
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

String _humanise(Object e) {
  if (e is ApiException) return e.message;
  return 'Network error';
}
