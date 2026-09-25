// =============================================================================
// SMART ROUTE PROVIDER  (Master Sprint, 2026-05-27)
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

double _num(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

class SmartRoute {
  final String id;
  final String name;
  final String action; // WITHDRAW_MOMO | INTERNAL_TRANSFER | SAVINGS_DEPOSIT | VAULT_DEPOSIT
  final double amountUsdc;
  final String frequency; // DAILY | WEEKLY | MONTHLY | ON_DAY_OF_MONTH
  final int? dayOfMonth;
  final String status; // ACTIVE | PAUSED | CANCELLED | COMPLETED
  final String? destMomoNumber;
  final String? destMomoProvider;
  final int? destFriendUserId;
  final String? destSavingsGoalId;
  final String? destVaultId;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final int totalRuns;
  final double totalRoutedUsdc;

  SmartRoute({
    required this.id,
    required this.name,
    required this.action,
    required this.amountUsdc,
    required this.frequency,
    this.dayOfMonth,
    required this.status,
    this.destMomoNumber,
    this.destMomoProvider,
    this.destFriendUserId,
    this.destSavingsGoalId,
    this.destVaultId,
    required this.startDate,
    this.endDate,
    required this.nextRunAt,
    this.lastRunAt,
    required this.totalRuns,
    required this.totalRoutedUsdc,
  });

  factory SmartRoute.fromJson(Map<String, dynamic> j) => SmartRoute(
        id: j['id'],
        name: j['name'],
        action: j['action'],
        amountUsdc: _num(j['amountUsdc']),
        frequency: j['frequency'],
        dayOfMonth: j['dayOfMonth'] != null ? (j['dayOfMonth'] as num).toInt() : null,
        status: j['status'],
        destMomoNumber: j['destMomoNumber'],
        destMomoProvider: j['destMomoProvider'],
        destFriendUserId:
            j['destFriendUserId'] != null ? (j['destFriendUserId'] as num).toInt() : null,
        destSavingsGoalId: j['destSavingsGoalId'],
        destVaultId: j['destVaultId'],
        startDate: DateTime.parse(j['startDate']),
        endDate: j['endDate'] != null ? DateTime.tryParse(j['endDate']) : null,
        nextRunAt: DateTime.parse(j['nextRunAt']),
        lastRunAt: j['lastRunAt'] != null ? DateTime.tryParse(j['lastRunAt']) : null,
        totalRuns: (j['totalRuns'] as num?)?.toInt() ?? 0,
        totalRoutedUsdc: _num(j['totalRoutedUsdc']),
      );
}

class SmartRouteRun {
  final String id;
  final String status;
  final double amountUsdc;
  final double? amountGhs;
  final String? failureReason;
  final DateTime createdAt;

  SmartRouteRun({
    required this.id,
    required this.status,
    required this.amountUsdc,
    this.amountGhs,
    this.failureReason,
    required this.createdAt,
  });

  factory SmartRouteRun.fromJson(Map<String, dynamic> j) => SmartRouteRun(
        id: j['id'],
        status: j['status'],
        amountUsdc: _num(j['amountUsdc']),
        amountGhs: j['amountGhs'] != null ? _num(j['amountGhs']) : null,
        failureReason: j['failureReason'],
        createdAt: DateTime.parse(j['createdAt']),
      );
}

class SmartRoutesNotifier extends AsyncNotifier<List<SmartRoute>> {
  @override
  Future<List<SmartRoute>> build() => _fetch();

  Future<List<SmartRoute>> _fetch() async {
    final res = await apiClient.get('/smart-routes');
    if (res.statusCode != 200) {
      throw Exception('Failed to load routes (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = body['routes'] as List<dynamic>? ?? const [];
    return list.map((e) => SmartRoute.fromJson(e)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<SmartRoute> create(Map<String, dynamic> body) async {
    final res = await apiClient.post('/smart-routes', body);
    if (res.statusCode != 201) throw Exception(_msg(res.body));
    await refresh();
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return SmartRoute.fromJson(j['route']);
  }

  Future<void> setStatus(String routeId, String status) async {
    final endpoint = status == 'PAUSED'
        ? '/smart-routes/$routeId/pause'
        : status == 'ACTIVE'
            ? '/smart-routes/$routeId/resume'
            : null;
    if (endpoint == null) {
      // CANCELLED → DELETE
      final res = await apiClient.delete('/smart-routes/$routeId');
      if (res.statusCode != 200) throw Exception(_msg(res.body));
    } else {
      final res = await apiClient.post(endpoint, {});
      if (res.statusCode != 200) throw Exception(_msg(res.body));
    }
    await refresh();
  }

  Future<void> runNow(String routeId) async {
    final res = await apiClient.post('/smart-routes/$routeId/run-now', {});
    if (res.statusCode != 200) throw Exception(_msg(res.body));
    await refresh();
  }

  String _msg(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['message']?.toString() ?? 'Smart route request failed';
    } catch (_) {
      return 'Smart route request failed';
    }
  }
}

final smartRoutesProvider =
    AsyncNotifierProvider<SmartRoutesNotifier, List<SmartRoute>>(SmartRoutesNotifier.new);

final smartRouteDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, routeId) async {
  final res = await apiClient.get('/smart-routes/$routeId');
  if (res.statusCode != 200) return null;
  return jsonDecode(res.body) as Map<String, dynamic>;
});
