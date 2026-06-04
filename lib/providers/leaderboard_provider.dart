// =============================================================================
// AZAMAN V3 — LEADERBOARD PROVIDER
//
// Riverpod ChangeNotifier for the Vendor Leaderboard.
// Fetches real data from GET /api/vendor/leaderboard and exposes:
//   - ranked vendor list
//   - current user's rank
//   - total vendor count
//   - active metric/tab selection
//   - loading / error / empty states
//
// Usage:
//   final lb = ref.watch(leaderboardProvider);
//   ref.read(leaderboardProvider).fetchLeaderboard();
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/leaderboard_service.dart';

/// Represents a single vendor entry on the leaderboard.
class LeaderboardEntry {
  final int rank;
  final int id;
  final String username;
  final int level;
  final int xp;
  final int tradesCompleted;
  final double totalVolume;
  final double totalProfit;
  final int streak;
  final int longestStreak;
  final double completionRate;
  final bool kycVerified;
  final bool isYou;

  const LeaderboardEntry({
    required this.rank,
    required this.id,
    required this.username,
    required this.level,
    required this.xp,
    required this.tradesCompleted,
    required this.totalVolume,
    required this.totalProfit,
    required this.streak,
    required this.longestStreak,
    required this.completionRate,
    required this.kycVerified,
    required this.isYou,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] ?? 0,
      id: json['id'] ?? 0,
      username: json['username'] ?? 'Unknown',
      level: json['level'] ?? 1,
      xp: json['xp'] ?? 0,
      tradesCompleted: json['tradesCompleted'] ?? 0,
      totalVolume: (json['totalVolume'] ?? 0).toDouble(),
      totalProfit: (json['totalProfit'] ?? 0).toDouble(),
      streak: json['streak'] ?? 0,
      longestStreak: json['longestStreak'] ?? 0,
      completionRate: (json['completionRate'] ?? 0).toDouble(),
      kycVerified: json['kycVerified'] ?? false,
      isYou: json['isYou'] ?? false,
    );
  }
}

/// Available leaderboard metrics (maps to backend query param)
enum LeaderboardMetric {
  xp,
  volume,
  trades,
  profit,
  streak;

  String get label {
    switch (this) {
      case LeaderboardMetric.xp:
        return 'XP';
      case LeaderboardMetric.volume:
        return 'VOLUME';
      case LeaderboardMetric.trades:
        return 'TRADES';
      case LeaderboardMetric.profit:
        return 'PROFIT';
      case LeaderboardMetric.streak:
        return 'STREAK';
    }
  }

  String get queryValue => name;
}

class LeaderboardProvider with ChangeNotifier {
  final LeaderboardService _service = LeaderboardService();

  // ── State ─────────────────────────────────────────────────────────────────
  List<LeaderboardEntry> entries = [];
  int? myRank;
  int totalVendors = 0;
  LeaderboardMetric activeMetric = LeaderboardMetric.xp;
  bool isLoading = false;
  String? error;

  LeaderboardProvider() {
    fetchLeaderboard();
  }

  // ===========================================================================
  // DATA FETCHING
  // ===========================================================================

  /// Fetch leaderboard for the currently active metric.
  Future<void> fetchLeaderboard({LeaderboardMetric? metric}) async {
    if (metric != null && metric != activeMetric) {
      activeMetric = metric;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final data = await _service.getLeaderboard(
        metric: activeMetric.queryValue,
        limit: 20,
      );

      final rawList = data['leaderboard'] as List<dynamic>? ?? [];
      entries = rawList
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      myRank = data['myRank'] as int?;
      totalVendors = data['totalVendors'] as int? ?? 0;
      error = null;
    } catch (e) {
      debugPrint('[LeaderboardProvider] fetchLeaderboard error: $e');
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Switch metric tab and reload data.
  Future<void> switchMetric(LeaderboardMetric metric) async {
    if (metric == activeMetric && entries.isNotEmpty) return;
    await fetchLeaderboard(metric: metric);
  }

  /// Pull-to-refresh: re-fetches current metric.
  Future<void> refresh() async {
    await fetchLeaderboard();
  }
}

// =============================================================================
// RIVERPOD HANDLE
// =============================================================================
final leaderboardProvider =
    ChangeNotifierProvider<LeaderboardProvider>((ref) {
  return LeaderboardProvider();
});
