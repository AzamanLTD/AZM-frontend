// =============================================================================
// HOLOGRAM LEDGER — RIVERPOD STATE LAYER (V5)
//
// Balance values are authoritative USDC ledger values. GHS is derived for
// display only using the backend oracle rate. Realtime balance events are
// convergence signals and trigger a canonical REST refresh rather than
// becoming a second source of financial truth.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:azaman/config.dart';

class BalanceData {
  final double availableBalance;
  final double vendorUnallocatedBalance;
  final double escrowLockedBalance;
  final double disputeEscrowBalance;
  final double azmBalance;

  const BalanceData({
    this.availableBalance = 0.0,
    this.vendorUnallocatedBalance = 0.0,
    this.escrowLockedBalance = 0.0,
    this.disputeEscrowBalance = 0.0,
    this.azmBalance = 0.0,
  });

  double get totalBalance => availableBalance + vendorUnallocatedBalance;
  double get totalLocked => escrowLockedBalance + disputeEscrowBalance;
  double get netWorth => totalBalance + totalLocked + azmBalance;

  factory BalanceData.fromJson(Map<String, dynamic> json) => BalanceData(
        availableBalance: _toDouble(json['availableBalance']),
        vendorUnallocatedBalance: _toDouble(json['vendorUnallocatedBalance']),
        escrowLockedBalance: _toDouble(json['escrowLockedBalance']),
        disputeEscrowBalance: _toDouble(json['disputeEscrowBalance']),
        azmBalance: _toDouble(json['azmBalance']),
      );

  BalanceData copyWith({
    double? availableBalance,
    double? vendorUnallocatedBalance,
    double? escrowLockedBalance,
    double? disputeEscrowBalance,
    double? azmBalance,
  }) => BalanceData(
        availableBalance: availableBalance ?? this.availableBalance,
        vendorUnallocatedBalance: vendorUnallocatedBalance ?? this.vendorUnallocatedBalance,
        escrowLockedBalance: escrowLockedBalance ?? this.escrowLockedBalance,
        disputeEscrowBalance: disputeEscrowBalance ?? this.disputeEscrowBalance,
        azmBalance: azmBalance ?? this.azmBalance,
      );
}

final balanceDataProvider = StateProvider<BalanceData>((ref) => const BalanceData());
final userUsdcBalanceProvider = StateProvider<double>((ref) => 0.0);

Future<void>? _balanceRefreshFuture;

Future<void> refreshCanonicalBalance(dynamic ref) {
  final existing = _balanceRefreshFuture;
  if (existing != null) return existing;

  final future = () async {
    if (AppConfig.demoMode) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) return;

      final response = await http
          .get(
            Uri.parse('${AppConfig.apiUrl}/users/balance'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;
      final rawData = decoded['data'];
      if (rawData is! Map<String, dynamic>) return;

      final balances = BalanceData.fromJson(rawData);
      ref.read(balanceDataProvider.notifier).state = balances;
      ref.read(userUsdcBalanceProvider.notifier).state = balances.totalBalance;
    } catch (_) {
      // Realtime convergence is best-effort. Keep the last known canonical
      // balance and let the next event or foreground refresh retry.
    }
  }();

  _balanceRefreshFuture = future;
  return future.whenComplete(() {
    if (identical(_balanceRefreshFuture, future)) _balanceRefreshFuture = null;
  });
}

class OracleRateMetadata {
  final DateTime fetchedAt;
  final DateTime? sourceLastSync;
  final Duration refreshInterval;
  final bool stale;

  const OracleRateMetadata({
    required this.fetchedAt,
    this.sourceLastSync,
    this.refreshInterval = const Duration(seconds: 60),
    this.stale = false,
  });

  Duration get timeUntilRefresh {
    final remaining = refreshInterval - DateTime.now().difference(fetchedAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get progress {
    if (refreshInterval.inMilliseconds <= 0) return 1.0;
    return (timeUntilRefresh.inMilliseconds / refreshInterval.inMilliseconds).clamp(0.0, 1.0);
  }
}

final oracleRateMetadataProvider = StateProvider<OracleRateMetadata>((ref) =>
    OracleRateMetadata(fetchedAt: DateTime.now(), stale: true));

final StateProvider<double> oracleRateProvider = StateProvider<double>((ref) {
  const fallbackRate = 12.50;
  const refreshSeconds = 60;

  Future<void> refresh() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.apiUrl}/oracle/rates'))
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      // /api/oracle/rates is wrapped as { success, data }. Keep a small
      // compatibility fallback for older deployments that returned the rate
      // object at the top level.
      final payload = decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : decoded;

      // USDC is authoritative for settlement; liveRetailRate is the server
      // rate intended for the end-user GHS presentation layer. Fall back to
      // liveUsdToGhs only for compatibility with older server data.
      final rawRate = payload['liveRetailRate'] ??
          payload['liveUsdToGhs'] ??
          payload['rate'];
      final rate = rawRate is num
          ? rawRate.toDouble()
          : double.tryParse(rawRate?.toString() ?? '') ?? 0;
      if (rate <= 0) return;

      final configuredSecondsRaw =
          payload['refreshIntervalSeconds'] ?? payload['quoteValiditySeconds'];
      final configuredSeconds = configuredSecondsRaw is num
          ? configuredSecondsRaw.toDouble()
          : double.tryParse(configuredSecondsRaw?.toString() ?? '') ?? 0;
      final interval = configuredSeconds > 0
          ? Duration(seconds: configuredSeconds.round())
          : const Duration(seconds: refreshSeconds);

      ref.read(oracleRateProvider.notifier).state = rate;
      ref.read(oracleRateMetadataProvider.notifier).state = OracleRateMetadata(
        fetchedAt: DateTime.now(),
        sourceLastSync: DateTime.tryParse(payload['lastSync']?.toString() ?? ''),
        refreshInterval: interval,
        stale: false,
      );
    } catch (_) {
      final current = ref.read(oracleRateMetadataProvider);
      ref.read(oracleRateMetadataProvider.notifier).state = OracleRateMetadata(
        fetchedAt: current.fetchedAt,
        sourceLastSync: current.sourceLastSync,
        refreshInterval: current.refreshInterval,
        stale: true,
      );
    }
  }

  final timer = Timer.periodic(const Duration(seconds: refreshSeconds), (_) => refresh());
  ref.onDispose(timer.cancel);
  Future.microtask(refresh);
  return fallbackRate;
});

final hologramBalanceProvider = Provider<double>((ref) {
  final balances = ref.watch(balanceDataProvider);
  final rate = ref.watch(oracleRateProvider);
  return balances.totalBalance * rate;
});

final balanceVisibleProvider = StateProvider<bool>((ref) => true);

final availableBalanceProvider = Provider<double>((ref) =>
    ref.watch(balanceDataProvider).availableBalance);

final escrowBalanceProvider = Provider<double>((ref) =>
    ref.watch(balanceDataProvider).escrowLockedBalance);

final azmBalanceProvider = Provider<double>((ref) =>
    ref.watch(balanceDataProvider).azmBalance);

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
