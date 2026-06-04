// =============================================================================
// AZAMAN — AZM REWARD SERVICE (Phase E1-FE)
//
// HTTP client for the /api/azm/* endpoints:
//   GET /api/azm/history  — paginated earn history
//   GET /api/azm/summary  — aggregate stats by source
//   GET /api/azm/rates    — current earn rate schedule (public)
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class AzmRewardEntry {
  final String id;
  final double amount;
  final String reason;
  final String source;
  final Map<String, dynamic>? metadata;
  final double balanceAfter;
  final DateTime createdAt;

  const AzmRewardEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.source,
    this.metadata,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory AzmRewardEntry.fromJson(Map<String, dynamic> json) {
    return AzmRewardEntry(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String,
      source: json['source'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      balanceAfter: (json['balanceAfter'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Human-friendly source label
  String get sourceLabel {
    switch (source) {
      case 'TRADE_COMPLETE':
        return 'Trade';
      case 'LOGIN_STREAK':
        return 'Login Streak';
      case 'REFERRAL_BONUS':
        return 'Referral';
      case 'ACHIEVEMENT_UNLOCK':
        return 'Achievement';
      case 'MILESTONE':
        return 'Milestone';
      default:
        return source;
    }
  }

  /// Source-specific icon
  String get sourceIcon {
    switch (source) {
      case 'TRADE_COMPLETE':
        return '🤝';
      case 'LOGIN_STREAK':
        return '🔥';
      case 'REFERRAL_BONUS':
        return '👥';
      case 'ACHIEVEMENT_UNLOCK':
        return '🏆';
      case 'MILESTONE':
        return '🎯';
      default:
        return '💎';
    }
  }
}

class AzmSummary {
  final double totalEarned;
  final double currentBalance;
  final Map<String, AzmSourceStats> bySource;

  const AzmSummary({
    required this.totalEarned,
    required this.currentBalance,
    required this.bySource,
  });

  factory AzmSummary.fromJson(Map<String, dynamic> json) {
    final bySourceRaw = json['bySource'] as Map<String, dynamic>? ?? {};
    final bySource = <String, AzmSourceStats>{};
    for (final entry in bySourceRaw.entries) {
      final data = entry.value as Map<String, dynamic>;
      bySource[entry.key] = AzmSourceStats(
        total: (data['total'] as num?)?.toDouble() ?? 0.0,
        count: (data['count'] as num?)?.toInt() ?? 0,
      );
    }
    return AzmSummary(
      totalEarned: (json['totalEarned'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (json['currentBalance'] as num?)?.toDouble() ?? 0.0,
      bySource: bySource,
    );
  }
}

class AzmSourceStats {
  final double total;
  final int count;

  const AzmSourceStats({required this.total, required this.count});
}

class AzmRates {
  final double tradeComplete;
  final double loginStreakDaily;
  final double loginStreak7Day;
  final double loginStreak30Day;
  final double loginStreak90Day;
  final double referral;
  final Map<String, double> achievements;
  final Map<String, double> milestones;

  const AzmRates({
    required this.tradeComplete,
    required this.loginStreakDaily,
    required this.loginStreak7Day,
    required this.loginStreak30Day,
    required this.loginStreak90Day,
    required this.referral,
    required this.achievements,
    required this.milestones,
  });

  factory AzmRates.fromJson(Map<String, dynamic> json) {
    final rates = json['rates'] as Map<String, dynamic>? ?? {};
    final tc = rates['tradeComplete'] as Map<String, dynamic>? ?? {};
    final ls = rates['loginStreak'] as Map<String, dynamic>? ?? {};
    final ref = rates['referral'] as Map<String, dynamic>? ?? {};
    final ach = rates['achievements'] as Map<String, dynamic>? ?? {};
    final mil = rates['milestones'] as Map<String, dynamic>? ?? {};

    return AzmRates(
      tradeComplete: (tc['amount'] as num?)?.toDouble() ?? 5.0,
      loginStreakDaily: (ls['daily'] as num?)?.toDouble() ?? 1.0,
      loginStreak7Day: (ls['bonus7Day'] as num?)?.toDouble() ?? 5.0,
      loginStreak30Day: (ls['bonus30Day'] as num?)?.toDouble() ?? 20.0,
      loginStreak90Day: (ls['bonus90Day'] as num?)?.toDouble() ?? 50.0,
      referral: (ref['amount'] as num?)?.toDouble() ?? 10.0,
      achievements: {
        'COMMON': (ach['COMMON'] as num?)?.toDouble() ?? 2.0,
        'RARE': (ach['RARE'] as num?)?.toDouble() ?? 5.0,
        'EPIC': (ach['EPIC'] as num?)?.toDouble() ?? 10.0,
        'LEGENDARY': (ach['LEGENDARY'] as num?)?.toDouble() ?? 25.0,
      },
      milestones: {
        '\$1k': (mil['volume1k'] as num?)?.toDouble() ?? 50.0,
        '\$10k': (mil['volume10k'] as num?)?.toDouble() ?? 100.0,
        '\$50k': (mil['volume50k'] as num?)?.toDouble() ?? 200.0,
        '\$100k': (mil['volume100k'] as num?)?.toDouble() ?? 500.0,
      },
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class AzmRewardService {
  /// Fetch paginated AZM earn history.
  Future<({List<AzmRewardEntry> rewards, String? nextCursor, bool hasMore})>
      getHistory({String? cursor, int limit = 20, String? source}) async {
    final params = <String, String>{'limit': '$limit'};
    if (cursor != null) params['cursor'] = cursor;
    if (source != null) params['source'] = source;

    final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final response = await apiClient.get('/azm/history?$queryString');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;

    final rewardsList = (data['rewards'] as List)
        .map((r) => AzmRewardEntry.fromJson(r as Map<String, dynamic>))
        .toList();

    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

    return (
      rewards: rewardsList,
      nextCursor: pagination['nextCursor'] as String?,
      hasMore: pagination['hasMore'] as bool? ?? false,
    );
  }

  /// Fetch aggregated AZM summary.
  Future<AzmSummary> getSummary() async {
    final response = await apiClient.get('/azm/summary');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AzmSummary.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// Fetch current earn rates (public, no auth).
  Future<AzmRates> getRates() async {
    final response = await apiClient.get('/azm/rates', requireAuth: false);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AzmRates.fromJson(body['data'] as Map<String, dynamic>);
  }
}

/// Singleton instance
final AzmRewardService azmRewardService = AzmRewardService();
