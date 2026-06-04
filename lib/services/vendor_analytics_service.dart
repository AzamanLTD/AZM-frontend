import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// AZAMAN — VENDOR ANALYTICS SERVICE (Phase Q16-FE)
//
// Calls GET /api/vendor/analytics?period=7d|30d|90d (auth required).
// Returns aggregated vendor performance data: summary stats, daily volume
// timeline, and payment method breakdown.
// =============================================================================

// ── Models ──────────────────────────────────────────────────────────────────

class VendorAnalyticsSummary {
  final int totalTrades;
  final double totalVolume;
  final double totalRevenue;
  final double avgCompletionMinutes;
  final double disputeRate;
  final int disputesInPeriod;
  final int allTimeTrades;

  const VendorAnalyticsSummary({
    required this.totalTrades,
    required this.totalVolume,
    required this.totalRevenue,
    required this.avgCompletionMinutes,
    required this.disputeRate,
    required this.disputesInPeriod,
    required this.allTimeTrades,
  });

  factory VendorAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return VendorAnalyticsSummary(
      totalTrades: (json['totalTrades'] as num?)?.toInt() ?? 0,
      totalVolume: (json['totalVolume'] as num?)?.toDouble() ?? 0.0,
      totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0.0,
      avgCompletionMinutes: (json['avgCompletionMinutes'] as num?)?.toDouble() ?? 0.0,
      disputeRate: (json['disputeRate'] as num?)?.toDouble() ?? 0.0,
      disputesInPeriod: (json['disputesInPeriod'] as num?)?.toInt() ?? 0,
      allTimeTrades: (json['allTimeTrades'] as num?)?.toInt() ?? 0,
    );
  }
}

class VolumeDataPoint {
  final String date;
  final double volume;
  final int trades;
  final double revenue;

  const VolumeDataPoint({
    required this.date,
    required this.volume,
    required this.trades,
    required this.revenue,
  });

  factory VolumeDataPoint.fromJson(Map<String, dynamic> json) {
    return VolumeDataPoint(
      date: json['date'] as String? ?? '',
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      trades: (json['trades'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MethodBreakdownEntry {
  final String method;
  final double volume;
  final int trades;
  final double revenue;

  const MethodBreakdownEntry({
    required this.method,
    required this.volume,
    required this.trades,
    required this.revenue,
  });

  factory MethodBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return MethodBreakdownEntry(
      method: json['method'] as String? ?? 'Unknown',
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      trades: (json['trades'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class VendorAnalyticsData {
  final String period;
  final int days;
  final VendorAnalyticsSummary summary;
  final List<VolumeDataPoint> volumeTimeline;
  final List<MethodBreakdownEntry> methodBreakdown;

  const VendorAnalyticsData({
    required this.period,
    required this.days,
    required this.summary,
    required this.volumeTimeline,
    required this.methodBreakdown,
  });

  factory VendorAnalyticsData.fromJson(Map<String, dynamic> json) {
    return VendorAnalyticsData(
      period: json['period'] as String? ?? '30d',
      days: (json['days'] as num?)?.toInt() ?? 30,
      summary: VendorAnalyticsSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? {},
      ),
      volumeTimeline: (json['volumeTimeline'] as List<dynamic>?)
              ?.map((e) => VolumeDataPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      methodBreakdown: (json['methodBreakdown'] as List<dynamic>?)
              ?.map((e) => MethodBreakdownEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// ── Service ─────────────────────────────────────────────────────────────────

class VendorAnalyticsService {
  /// Fetch vendor analytics for the given period.
  /// [period] must be one of: '7d', '30d', '90d'.
  Future<VendorAnalyticsData> fetchAnalytics(String period) async {
    try {
      final response = await apiClient.get(
        '/vendor/analytics?period=$period',
        requireAuth: true,
      );

      final body = jsonDecode(response.body);

      if (body['success'] == true && body['data'] != null) {
        return VendorAnalyticsData.fromJson(body['data'] as Map<String, dynamic>);
      }

      throw Exception(body['message'] ?? 'Failed to fetch analytics');
    } catch (e) {
      debugPrint('[VendorAnalyticsService] fetchAnalytics error: $e');
      rethrow;
    }
  }
}

/// Singleton instance
final VendorAnalyticsService vendorAnalyticsService = VendorAnalyticsService();
