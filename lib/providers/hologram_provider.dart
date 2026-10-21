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
import 'package:azaman/config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:azaman/providers/currency_provider.dart' show parseFxRateSnapshot;
import 'package:azaman/services/oracle_rates_client.dart';

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

/// WORKSTREAM B — an explicit hydration state for the canonical balance.
/// The provider's default [BalanceData] is all zeros, and a default object
/// with 0.00 values is NOT evidence that the server confirmed a zero
/// balance. Until an authoritative fetch completes, the amount slot must
/// not print a number at all.
///
/// * [unresolved] — no authoritative balance has arrived yet (initial
///   state; the amount slot shows the waiting indicator, never "0.00").
/// * [loaded] — the server confirmed a balance, INCLUDING a genuine zero.
/// * [failed] — the request failed and NO usable value has ever been
///   loaded. A failure AFTER a successful load keeps [loaded]: the last
///   confirmed figure is still the honest number, and a later refresh
///   can update it.
enum BalanceReadiness { unresolved, loaded, failed }

/// The canonical balance readiness, driven by [refreshCanonicalBalance]
/// and the login-path balance seeding in auth_provider.
final balanceReadinessProvider =
    StateProvider<BalanceReadiness>((ref) => BalanceReadiness.unresolved);
final userUsdcBalanceProvider = StateProvider<double>((ref) => 0.0);

/// IDENTITY BOUNDARIES (review follow-up) — an in-flight balance refresh
/// belongs to the session identity that started it. AuthProvider bumps
/// this epoch at every identity boundary (logout, invalid-profile
/// teardown, user switch). A refresh captured under a stale epoch must
/// not write balance data, readiness, or a failure mark for the new
/// identity: "preserve the last confirmed balance on refresh failure"
/// holds ONLY for the same identity.
final balanceEpochProvider = StateProvider<int>((ref) => 0);

/// Test seam: lets integration tests stub the network without hitting a
/// real endpoint. Production code never sets it.
@visibleForTesting
http.Client? balanceRefreshClientOverride;

Future<void>? _balanceRefreshFuture;

Future<void> refreshCanonicalBalance(dynamic ref) {
  final existing = _balanceRefreshFuture;
  if (existing != null) return existing;

  final future = () async {
    if (AppConfig.demoMode) return;
    // IDENTITY BOUNDARIES — capture the epoch this attempt belongs to.
    final epoch = ref.read(balanceEpochProvider);
    bool isStale() => ref.read(balanceEpochProvider) != epoch;
    // WORKSTREAM B — an early return or thrown error means no balance came
    // back from this attempt. That is only a FAILURE if nothing usable has
    // ever loaded; after a successful load the last confirmed figure stays
    // authoritative and readiness remains `loaded`.
    void markFailed() {
      if (isStale()) return; // never write failure for another identity
      final notifier = ref.read(balanceReadinessProvider.notifier);
      if (notifier.state != BalanceReadiness.loaded) {
        notifier.state = BalanceReadiness.failed;
      }
    }

    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token');
      if (token == null || token.isEmpty) {
        markFailed();
        return;
      }

      final response = await (balanceRefreshClientOverride ?? http.Client())
          .get(
            Uri.parse('${AppConfig.apiUrl}/users/balance'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(AppConfig.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        markFailed();
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        markFailed();
        return;
      }
      final rawData = decoded['data'];
      if (rawData is! Map<String, dynamic>) {
        markFailed();
        return;
      }

      final balances = BalanceData.fromJson(rawData);
      if (isStale()) return; // never write data for another identity
      ref.read(balanceDataProvider.notifier).state = balances;
      ref.read(userUsdcBalanceProvider.notifier).state = balances.totalBalance;
      // The server has confirmed a balance — a genuine 0.00 included.
      ref.read(balanceReadinessProvider.notifier).state =
          BalanceReadiness.loaded;
    } catch (_) {
      // Realtime convergence is best-effort. Keep the last known canonical
      // balance and let the next event or foreground refresh retry.
      markFailed();
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

Map<String, dynamic> _unwrapOraclePayload(Map<String, dynamic> decoded) {
  final data = decoded['data'];
  return data is Map<String, dynamic> ? data : decoded;
}

double _positiveDouble(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return number > 0 && number.isFinite ? number : 0;
}

bool _isCanonicalUsdcGhs(Map<String, dynamic> payload) {
  return payload['pair']?.toString().toUpperCase() == 'USDC/GHS' &&
      payload['settlementCurrency']?.toString().toUpperCase() == 'USDC' &&
      payload['displayCurrency']?.toString().toUpperCase() == 'GHS';
}

double parseOracleGhsRate(Map<String, dynamic> decoded) {
  final payload = _unwrapOraclePayload(decoded);
  if (!_isCanonicalUsdcGhs(payload)) return 0;
  return _positiveDouble(payload['liveRetailRate']);
}

final StateProvider<double> oracleRateProvider = StateProvider<double>((ref) {
  const refreshSeconds = 60;

  Future<void> refresh() async {
    try {
      // §9 startup audit: the poller used to issue its own raw http.get to
      // the same endpoint the home summary, FX and Susu providers fetch —
      // and it bypassed the apiClient (so no demo-mode interceptor). It
      // now shares the single-flight [getOracleRates] request.
      final response = await getOracleRates();
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      final payload = _unwrapOraclePayload(decoded);
      // §5: the Home equivalent now uses the SAME canonical freshness
      // rule as the Send path — parseFxRateSnapshot requires the
      // backend's isFresh/lastExternalSync/threshold contract. An old
      // server observation (or missing metadata) keeps the rate at 0 =
      // "unavailable", never a silent live-looking figure.
      final snapshot = parseFxRateSnapshot(payload);
      if (!snapshot.isUsable) return;
      final rate = snapshot.ghsPerUsdc;

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
      // A usable snapshot still carries its true expiry: surface the
      // moment it ages out so the card's countdown stays honest.
      final staleAt = snapshot.staleAt;
      if (staleAt != null) {
        ref.read(oracleRateStaleAtProvider.notifier).state = staleAt;
      }
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
  // Never inject a fabricated or legacy FX rate. Until the server returns a
  // valid canonical USDC/GHS retail rate, GHS presentation remains
  // unavailable while USDC stays authoritative.
  return 0.0;
});

/// The moment the CURRENT oracle observation ages out under the
/// backend's freshness threshold — informational for UI countdowns.
final StateProvider<DateTime?> oracleRateStaleAtProvider =
    StateProvider<DateTime?>((ref) => null);

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
