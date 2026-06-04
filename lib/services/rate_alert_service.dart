import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:azaman/services/api_client.dart';

// =============================================================================
// AZAMAN — RATE ALERT SERVICE (Phase Q12-FE)
//
// Wraps the backend endpoints:
//   POST   /api/oracle/alerts      — create alert
//   GET    /api/oracle/alerts      — list alerts + currentRate
//   DELETE /api/oracle/alerts/:id  — delete alert
// =============================================================================

class RateAlert {
  final String id;
  final double targetRate;
  final String direction; // "ABOVE" or "BELOW"
  final String ratePair;
  final String? note;
  final String status; // "ACTIVE" or "TRIGGERED"
  final DateTime? triggeredAt;
  final double? triggeredRate;
  final DateTime createdAt;

  const RateAlert({
    required this.id,
    required this.targetRate,
    required this.direction,
    required this.ratePair,
    this.note,
    required this.status,
    this.triggeredAt,
    this.triggeredRate,
    required this.createdAt,
  });

  bool get isTriggered => status == 'TRIGGERED';
  bool get isActive => status == 'ACTIVE';

  factory RateAlert.fromJson(Map<String, dynamic> json) {
    return RateAlert(
      id: json['id']?.toString() ?? '',
      targetRate: (json['targetRate'] as num?)?.toDouble() ?? 0.0,
      direction: json['direction'] as String? ?? 'ABOVE',
      ratePair: json['ratePair'] as String? ?? 'USD_GHS',
      note: json['note'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.tryParse(json['triggeredAt'].toString())
          : null,
      triggeredRate: (json['triggeredRate'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RateAlertListResponse {
  final List<RateAlert> alerts;
  final double? currentRate;
  final String ratePair;

  const RateAlertListResponse({
    required this.alerts,
    this.currentRate,
    required this.ratePair,
  });
}

class RateAlertService {
  /// Create a new rate alert.
  Future<RateAlert> createAlert({
    required double targetRate,
    required String direction,
    String? note,
  }) async {
    final response = await apiClient.post(
      '/oracle/alerts',
      {
        'targetRate': targetRate,
        'direction': direction,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      requireAuth: true,
    );

    final body = jsonDecode(response.body);
    if (body['success'] == true && body['data'] != null) {
      return RateAlert.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw Exception(body['message'] ?? 'Failed to create alert');
  }

  /// List all alerts for the authenticated user.
  Future<RateAlertListResponse> listAlerts() async {
    final response = await apiClient.get(
      '/oracle/alerts',
      requireAuth: true,
    );

    final body = jsonDecode(response.body);
    if (body['success'] == true && body['data'] != null) {
      final data = body['data'] as Map<String, dynamic>;
      final alertsList = (data['alerts'] as List<dynamic>?)
              ?.map((e) => RateAlert.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      return RateAlertListResponse(
        alerts: alertsList,
        currentRate: (data['currentRate'] as num?)?.toDouble(),
        ratePair: data['ratePair'] as String? ?? 'USD_GHS',
      );
    }
    throw Exception(body['message'] ?? 'Failed to fetch alerts');
  }

  /// Delete a rate alert by ID.
  Future<void> deleteAlert(String alertId) async {
    try {
      await apiClient.delete(
        '/oracle/alerts/$alertId',
        requireAuth: true,
      );
    } catch (e) {
      debugPrint('[RateAlertService] deleteAlert error: $e');
      rethrow;
    }
  }
}

/// Singleton instance
final RateAlertService rateAlertService = RateAlertService();
