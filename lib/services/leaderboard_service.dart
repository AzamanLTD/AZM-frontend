// =============================================================================
// AZAMAN V3 — LEADERBOARD SERVICE
//
// Wraps GET /api/vendor/leaderboard endpoint using the centralized ApiClient.
// Returns top vendors ranked by metric (xp, volume, trades, profit, streak).
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';

class LeaderboardService {
  static final LeaderboardService _instance = LeaderboardService._internal();
  factory LeaderboardService() => _instance;
  LeaderboardService._internal();

  /// Fetch vendor leaderboard from backend.
  ///
  /// [metric] — ranking metric: xp | volume | trades | profit | streak (default: xp)
  /// [limit]  — max vendors to return (default: 20, max: 50)
  ///
  /// Returns decoded response map:
  /// { metric, myRank, totalVendors, leaderboard: [ { rank, id, username, level, xp,
  ///   tradesCompleted, totalVolume, totalProfit, streak, longestStreak,
  ///   completionRate, kycVerified, isYou } ] }
  Future<Map<String, dynamic>> getLeaderboard({
    String metric = 'xp',
    int limit = 20,
  }) async {
    final response = await apiClient.get(
      '/vendor/leaderboard?metric=$metric&limit=$limit',
    );

    final body = jsonDecode(response.body);
    if (body['success'] == true) {
      return body['data'] as Map<String, dynamic>;
    }
    throw ApiException(
      message: body['message'] ?? 'Failed to fetch leaderboard',
      statusCode: response.statusCode,
    );
  }
}
