import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/services/oracle_rates_client.dart';

/// Server-authoritative FX snapshot. USDC is the financial/settlement unit of
/// account; GHS is a derived local presentation value from the backend's
/// current user-facing retail rate.
class FxRateSnapshot {
  final double ghsPerUsdc;
  final String source;
  final DateTime? lastSync;
  final DateTime fetchedAt;
  final String pair;
  final String settlementCurrency;
  final String displayCurrency;
  final bool isCanonical;

  // ── The backend's rate-freshness contract (PR #165 review §2) ─────────
  // The backend's /api/oracle/rates freshness gate (271C) is anchored to
  // the LAST EXTERNAL market observation (lastExternalSync), bounded by
  // rateFreshnessMaxAgeSeconds. `fetchedAt` is when THIS client received
  // the HTTP response — it is informational only and can NEVER make an
  // old server observation appear fresh: every usability check recomputes
  // the observation age from lastExternalSync against the caller's clock.
  final bool serverFresh;
  final DateTime? lastExternalSync;
  final int? externalRateAgeSeconds;
  final double rateFreshnessMaxAgeSeconds;

  /// Mirrors the backend's own tiny skew allowance: an external
  /// observation further in the future than 5s is untrusted, never
  /// "infinitely fresh" (rateFreshness.js — RATE_FRESHNESS_CLOCK_SKEW_).
  static const clockSkewAllowance = Duration(seconds: 5);

  /// Contradiction tolerance between the server's observed age and ours
  /// (response travel time + minor clock skew). A wildly contradictory
  /// server age means the metadata is not trustworthy.
  static const ageContradictionToleranceSeconds = 30;

  const FxRateSnapshot({
    required this.ghsPerUsdc,
    required this.source,
    required this.lastSync,
    required this.fetchedAt,
    this.pair = 'USDC/GHS',
    this.settlementCurrency = 'USDC',
    this.displayCurrency = 'GHS',
    this.isCanonical = true,
    this.serverFresh = false,
    this.lastExternalSync,
    this.externalRateAgeSeconds,
    this.rateFreshnessMaxAgeSeconds = 0,
  });

  /// Additive test/diagnostic convenience: derive a snapshot with a few
  /// fields replaced, preserving the rest verbatim.
  /// Additive test/diagnostic convenience: derive a snapshot with a few
  /// fields replaced, preserving the rest verbatim. The two nullable
  /// metadata fields go through an [Object] sentinel so they CAN also be
  /// cleared to null by tests.
  FxRateSnapshot copyWith({
    Object? lastExternalSync = _sentinel,
    Object? externalRateAgeSeconds = _sentinel,
    double? rateFreshnessMaxAgeSeconds,
    bool? serverFresh,
    bool? isCanonical,
    double? ghsPerUsdc,
  }) => FxRateSnapshot(
    ghsPerUsdc: ghsPerUsdc ?? this.ghsPerUsdc,
    source: source,
    lastSync: lastSync,
    fetchedAt: fetchedAt,
    pair: pair,
    settlementCurrency: settlementCurrency,
    displayCurrency: displayCurrency,
    isCanonical: isCanonical ?? this.isCanonical,
    serverFresh: serverFresh ?? this.serverFresh,
    lastExternalSync: identical(lastExternalSync, _sentinel)
        ? this.lastExternalSync
        : lastExternalSync as DateTime?,
    externalRateAgeSeconds: identical(externalRateAgeSeconds, _sentinel)
        ? this.externalRateAgeSeconds
        : externalRateAgeSeconds as int?,
    rateFreshnessMaxAgeSeconds:
        rateFreshnessMaxAgeSeconds ?? this.rateFreshnessMaxAgeSeconds,
  );

  /// Whether the server's reported observation age contradicts the age
  /// this client computes from [lastExternalSync] at [now].
  ///
  /// The reported age is a POINT-IN-TIME observation captured when the
  /// response was fetched, so it ages in lockstep with ours: comparing
  /// the raw stored value against our ever-growing local age would make
  /// a consistent-at-receipt snapshot "contradictory" after ~30s even
  /// inside a 300s window. Re-anchoring by the time elapsed since
  /// [fetchedAt] keeps the discrepancy constant (response travel time
  /// plus minor clock skew), so a consistent observation stays consistent
  /// for its whole freshness window while a genuinely contradictory one
  /// is still rejected. Single source of truth: [isUsableAt] and the
  /// screen's disclosed reason both call this.
  bool serverAgeContradictsAt(DateTime now) {
    final reported = externalRateAgeSeconds;
    final observed = lastExternalSync;
    if (reported == null || observed == null) return false;
    final localAge = now.difference(observed).inMilliseconds / 1000.0;
    final elapsedSinceFetch = now.difference(fetchedAt).inMilliseconds / 1000.0;
    return ((reported + elapsedSinceFetch) - localAge).abs() >
        ageContradictionToleranceSeconds;
  }

  /// The FULL conversion gate: canonical USDC/GHS retail metadata, a
  /// positive finite rate, AND a genuinely fresh external observation —
  // the backend's `isFresh` verdict plus our own clock check against
  /// lastExternalSync (fetchedAt never substitutes for it).
  bool isUsableAt(DateTime now) {
    if (!isCanonical) return false;
    if (!ghsPerUsdc.isFinite || ghsPerUsdc <= 0) return false;
    if (!serverFresh) return false;
    if (lastExternalSync == null) return false;
    if (!rateFreshnessMaxAgeSeconds.isFinite ||
        rateFreshnessMaxAgeSeconds <= 0) {
      return false;
    }

    final ageSeconds =
        now.difference(lastExternalSync!).inMilliseconds / 1000.0;
    // Future-invalid: beyond the backend's own skew allowance an
    // observation in the future is untrusted, never infinitely fresh.
    if (ageSeconds < -clockSkewAllowance.inSeconds) return false;
    // Stale: the observation aged past the backend's own threshold.
    if (ageSeconds > rateFreshnessMaxAgeSeconds) return false;
    // The server's own age observation must not contradict ours.
    if (serverAgeContradictsAt(now)) return false;
    return true;
  }

  /// Usability at the caller's current clock. Callers holding a snapshot
  /// across time (a retained provider value) get a truthful verdict:
  /// an observation that has aged past the threshold stops converting
  /// even though the snapshot object still exists.
  bool get isUsable => isUsableAt(DateTime.now().toUtc());

  /// Honest countdown target for freshness-sensitive UI: the moment this
  /// observation becomes stale under the backend's threshold. The window
  /// is FLOAT seconds (the exact precision [isUsableAt] compares against),
  /// so the expiry must preserve its fractional part — rounding to whole
  /// seconds lets a one-shot re-check timer fire while the snapshot is
  /// still usable, re-arming a zero-delay timer every frame until the
  /// true threshold passes (and can equally delay the check past it).
  DateTime? get staleAt => lastExternalSync?.add(
    Duration(microseconds: (rateFreshnessMaxAgeSeconds * 1e6).round()),
  );

  double usdcToGhs(double usdc) => usdc * ghsPerUsdc;

  double ghsToUsdc(double ghs) => ghs / ghsPerUsdc;
}

double _positiveRate(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return number > 0 && number.isFinite ? number : 0;
}

double _positiveFiniteDouble(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return number.isFinite && number > 0 ? number : 0;
}

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

/// Converts a backend oracle payload into the typed client snapshot.
///
/// The canonical path requires an explicit positive `liveRetailRate`, the
/// USDC/GHS rail metadata, AND the backend's full freshness contract:
/// `isFresh == true`, a parseable `lastExternalSync` within
/// `rateFreshnessMaxAgeSeconds` of [now] (bounded by the backend's clock
/// skew allowance on the future side), and a `rateFreshnessMaxAgeSeconds`
/// the backend actually sent. Missing, stale, future-invalid, non-finite
/// or contradictory metadata yields a snapshot whose `isUsable` is false —
/// it is never silently treated as a live rate (PR #165 review §2).
///
/// Older `liveUsdToGhs` / `rate` values remain readable for compatibility,
/// but are marked non-canonical and therefore are never usable.
FxRateSnapshot parseFxRateSnapshot(Map<String, dynamic> data, {DateTime? now}) {
  // CLOCK DISCIPLINE — `fetchedAt` (when this client received the
  // response) and the freshness evaluation instant are ONE moment in
  // the parser: the injected [now] (tests) or the wall clock (live).
  // Stamping fetchedAt with the wall clock while evaluating freshness
  // against an injected clock would make the server-age re-anchoring
  // see a phantom elapsed-since-fetch and falsely flag contradictions.
  final fetchedNow = (now ?? DateTime.now()).toUtc();
  final retail = _positiveRate(data['liveRetailRate']);
  final headline = _positiveRate(data['liveUsdToGhs']);
  final legacy = _positiveRate(data['rate']);

  final pair = data['pair']?.toString() ?? 'USDC/GHS';
  final settlementCurrency = data['settlementCurrency']?.toString() ?? 'USDC';
  final displayCurrency = data['displayCurrency']?.toString() ?? 'GHS';
  final canonicalMetadata =
      pair == 'USDC/GHS' &&
      settlementCurrency == 'USDC' &&
      displayCurrency == 'GHS';

  final hasCanonicalRetail = retail > 0;
  final rate = hasCanonicalRetail
      ? retail
      : headline > 0
      ? headline
      : legacy;

  final lastExternalSync = DateTime.tryParse(
    data['lastExternalSync']?.toString() ?? '',
  )?.toUtc();
  final serverFresh = data['isFresh'] == true;
  final externalRateAgeSeconds = _intOrNull(data['externalRateAgeSeconds']);
  final rateFreshnessMaxAgeSeconds = _positiveFiniteDouble(
    data['rateFreshnessMaxAgeSeconds'],
  );

  final freshnessMetadataPresent =
      serverFresh && lastExternalSync != null && rateFreshnessMaxAgeSeconds > 0;

  if (rate <= 0) {
    return FxRateSnapshot(
      ghsPerUsdc: 0,
      source: 'UNAVAILABLE',
      lastSync: null,
      fetchedAt: fetchedNow,
      pair: pair,
      settlementCurrency: settlementCurrency,
      displayCurrency: displayCurrency,
      isCanonical: false,
    );
  }

  return FxRateSnapshot(
    ghsPerUsdc: rate,
    source: data['rateSource']?.toString() ?? 'UNKNOWN',
    lastSync: DateTime.tryParse(data['lastSync']?.toString() ?? ''),
    fetchedAt: fetchedNow,
    pair: pair,
    settlementCurrency: settlementCurrency,
    displayCurrency: displayCurrency,
    isCanonical:
        hasCanonicalRetail && canonicalMetadata && freshnessMetadataPresent,
    serverFresh: serverFresh,
    lastExternalSync: lastExternalSync,
    externalRateAgeSeconds: externalRateAgeSeconds,
    rateFreshnessMaxAgeSeconds: rateFreshnessMaxAgeSeconds,
  );
}

/// Reads the public backend oracle endpoint. The explicit retail field is the
/// canonical USDC/GHS display rate. Legacy headline fields may still be read
/// for compatibility, but the snapshot marks them as non-canonical so callers
/// never mistake a legacy USD/GHS value for a fresh Kotani retail quote.
final fxRateProvider = FutureProvider<FxRateSnapshot?>((ref) async {
  try {
    // §9: shares the single-flight oracle request (see oracle_rates_client).
    final response = await getOracleRates();
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['success'] != true) return null;

    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;

    // The snapshot is returned even when its freshness verdict is false:
    // callers gate on `isUsable` (recomputed against the caller's clock)
    // and can distinguish "stale but described" from "no data at all".
    // Nothing downstream can mistake it for a live rate.
    return parseFxRateSnapshot(data);
  } catch (_) {
    return null;
  }
});

/// Small reusable countdown model for quote-sensitive conversion UI.
class QuoteRefreshClock {
  final DateTime expiresAt;
  final Duration totalDuration;

  const QuoteRefreshClock({
    required this.expiresAt,
    required this.totalDuration,
  });

  Duration get remaining {
    final value = expiresAt.difference(DateTime.now().toUtc());
    return value.isNegative ? Duration.zero : value;
  }

  double get progress {
    if (totalDuration.inMilliseconds <= 0) return 0;
    final value = remaining.inMilliseconds / totalDuration.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }

  bool get expired => remaining == Duration.zero;
}

/// Invalidates the public FX snapshot. Screens with conversion-sensitive UI
/// can call `ref.invalidate(fxRateProvider)` after a refresh window expires.
void refreshFxRate(WidgetRef ref) => ref.invalidate(fxRateProvider);

/// Sentinel distinguishing an omitted copyWith argument from an
/// explicit null (both nullable metadata fields can be cleared).
const Object _sentinel = Object();
