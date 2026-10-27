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

  // ── Backend valuation block (backend PR #367, additive) ────────────────
  //
  // The balance response may carry `data.valuation`. The THREE states the
  // card adapter must distinguish live here:
  //   • [valuationFieldPresent] false — LEGACY response: the contract has
  //     not shipped; the adapter keeps its interim display-only derivation.
  //   • [valuationFieldPresent] true + [valuationRaw] null — the backend
  //     EXPLICITLY says valuation is unavailable. The card must NOT
  //     silently substitute a client-side conversion for that failure.
  //   • [valuationFieldPresent] true + a Map — the raw payload, strictly
  //     parsed later by BackendBalanceValuation.parse (a malformed
  //     payload rejects exactly like an explicit null).
  final bool valuationFieldPresent;
  final Map<String, dynamic>? valuationRaw;

  const BalanceData({
    this.availableBalance = 0.0,
    this.vendorUnallocatedBalance = 0.0,
    this.escrowLockedBalance = 0.0,
    this.disputeEscrowBalance = 0.0,
    this.azmBalance = 0.0,
    this.valuationFieldPresent = false,
    this.valuationRaw,
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
    bool? valuationFieldPresent,
    Map<String, dynamic>? valuationRaw,
  }) => BalanceData(
        availableBalance: availableBalance ?? this.availableBalance,
        vendorUnallocatedBalance: vendorUnallocatedBalance ?? this.vendorUnallocatedBalance,
        escrowLockedBalance: escrowLockedBalance ?? this.escrowLockedBalance,
        disputeEscrowBalance: disputeEscrowBalance ?? this.disputeEscrowBalance,
        azmBalance: azmBalance ?? this.azmBalance,
        valuationFieldPresent: valuationFieldPresent ?? this.valuationFieldPresent,
        valuationRaw: valuationRaw ?? this.valuationRaw,
      );

  /// STRICT production parse — the seam the canonical refresh uses.
  ///
  /// [BalanceData.fromJson] keeps its lenient legacy behaviour for the
  /// non-authoritative call sites that predate this law, but the refresh
  /// path must never turn a missing/malformed numeric field into a
  /// seemingly server-confirmed zero. Rules:
  ///   • every LEGACY balance field is required and must be a finite
  ///     number (a numeric string counts — the backend serializes
  ///     Decimals as strings); a GENUINE numeric zero is valid and stays
  ///     zero.
  ///   • any missing/malformed legacy field → the whole payload is
  ///     invalid (null): the refresh marks the attempt failed instead
  ///     of writing a fabricated balance.
  ///   • `valuation` key absent → legacy response ([valuationFieldPresent]
  ///     false); `valuation: null` → explicit unavailability (present,
  ///     raw null); a Map → carried raw for the typed strict parse.
  static BalanceData? tryParseValidPayload(Map<String, dynamic> json) {
    final availableBalance = _toDoubleStrict(json['availableBalance']);
    final vendorUnallocated =
        _toDoubleStrict(json['vendorUnallocatedBalance']);
    final escrowLocked = _toDoubleStrict(json['escrowLockedBalance']);
    final disputeEscrow = _toDoubleStrict(json['disputeEscrowBalance']);
    final azmBalance = _toDoubleStrict(json['azmBalance']);
    if (availableBalance == null ||
        vendorUnallocated == null ||
        escrowLocked == null ||
        disputeEscrow == null ||
        azmBalance == null) {
      return null;
    }

    bool valuationPresent = false;
    Map<String, dynamic>? valuationRaw;
    if (json.containsKey('valuation')) {
      valuationPresent = true;
      final raw = json['valuation'];
      if (raw is Map) {
        valuationRaw = Map<String, dynamic>.from(raw);
      } else {
        valuationRaw = null; // explicit backend unavailability
      }
    }

    return BalanceData(
      availableBalance: availableBalance,
      vendorUnallocatedBalance: vendorUnallocated,
      escrowLockedBalance: escrowLocked,
      disputeEscrowBalance: disputeEscrow,
      azmBalance: azmBalance,
      valuationFieldPresent: valuationPresent,
      valuationRaw: valuationRaw,
    );
  }
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
// IDENTITY BOUNDARIES — the single-flight slot belongs to the identity
// (epoch) that started the in-flight refresh. A NEW epoch may always
// start its own refresh instead of joining the previous identity's
// pending future: the stale-response guard would correctly discard that
// old response, but the new identity's request would then never run
// from this call.
int _balanceRefreshEpoch = -1;

Future<void> refreshCanonicalBalance(dynamic ref) {
  // Capture the epoch at entry so coalescing is identity-scoped AND the
  // attempt below belongs to the identity that initiated it.
  final epoch = ref.read(balanceEpochProvider);
  final existing = _balanceRefreshFuture;
  if (existing != null && _balanceRefreshEpoch == epoch) return existing;

  final future = () async {
    if (AppConfig.demoMode) return;
    // IDENTITY BOUNDARIES — this attempt belongs to [epoch]; a response
    // landing after the epoch moved belongs to a different identity.
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

      // Resource lifecycle — production must not own a client here:
      // package:http's top-level get() opens and closes a one-shot
      // client per request, so nothing leaks across realtime/
      // foreground refreshes. The test override stays under TEST
      // ownership: this code never creates (and so never needs to
      // close) the injected client.
      final response = await (balanceRefreshClientOverride != null
          ? balanceRefreshClientOverride!.get(
            Uri.parse('${AppConfig.apiUrl}/users/balance'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'Authorization': 'Bearer $token',
            },
          )
          : http.get(
            Uri.parse('${AppConfig.apiUrl}/users/balance'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'Authorization': 'Bearer $token',
            },
          ))
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

      // STRICT PARSE — a payload with missing/malformed legacy balance
      // fields is NOT a confirmed balance: writing the lenient zeros of
      // BalanceData.fromJson would display a fabricated 0.00 as though
      // the server confirmed it. Invalid → this attempt fails (the last
      // confirmed figure, if any, stays authoritative).
      final balances = BalanceData.tryParseValidPayload(rawData);
      if (balances == null) {
        markFailed();
        return;
      }
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
  _balanceRefreshEpoch = epoch;
  return future.whenComplete(() {
    if (identical(_balanceRefreshFuture, future)) {
      _balanceRefreshFuture = null;
      _balanceRefreshEpoch = -1;
    }
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

/// Strict variant for the AUTHORITATIVE refresh path: null (not zero)
/// when the field is missing, non-numeric or non-finite. A numeric
/// string is accepted (Prisma Decimals serialize as strings); a genuine
/// zero stays a real zero.
double? _toDoubleStrict(dynamic value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) {
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}
