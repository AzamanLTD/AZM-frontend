import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/models/currency_model.dart';
import 'package:azaman/services/api_client.dart';

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

  const FxRateSnapshot({
    required this.ghsPerUsdc,
    required this.source,
    required this.lastSync,
    required this.fetchedAt,
    this.pair = 'USDC/GHS',
    this.settlementCurrency = 'USDC',
    this.displayCurrency = 'GHS',
    this.isCanonical = true,
  });

  bool get isUsable =>
      ghsPerUsdc > 0 &&
      pair == 'USDC/GHS' &&
      settlementCurrency == 'USDC' &&
      displayCurrency == 'GHS' &&
      isCanonical;

  double usdcToGhs(double usdc) => usdc * ghsPerUsdc;

  double ghsToUsdc(double ghs) => ghs / ghsPerUsdc;
}

double _positiveRate(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return number > 0 && number.isFinite ? number : 0;
}

/// Converts a backend oracle payload into the typed client snapshot.
///
/// The canonical path requires an explicit positive `liveRetailRate` plus
/// explicit USDC/GHS rail metadata. Older `liveUsdToGhs` / `rate` values remain
/// readable for compatibility, but are marked non-canonical and therefore are
/// not safe for current conversion UI (`isUsable == false`).
FxRateSnapshot parseFxRateSnapshot(Map<String, dynamic> data) {
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
  final rate = hasCanonicalRetail ? retail : headline > 0 ? headline : legacy;
  if (rate <= 0) {
    return FxRateSnapshot(
      ghsPerUsdc: 0,
      source: 'UNAVAILABLE',
      lastSync: null,
      fetchedAt: DateTime.now().toUtc(),
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
    fetchedAt: DateTime.now().toUtc(),
    pair: pair,
    settlementCurrency: settlementCurrency,
    displayCurrency: displayCurrency,
    isCanonical: hasCanonicalRetail && canonicalMetadata,
  );
}

/// Reads the public backend oracle endpoint. The explicit retail field is the
/// canonical USDC/GHS display rate. Legacy headline fields may still be read
/// for compatibility, but the snapshot marks them as non-canonical so callers
/// never mistake a legacy USD/GHS value for a fresh Kotani retail quote.
final fxRateProvider = FutureProvider<FxRateSnapshot?>((ref) async {
  try {
    final response = await apiClient.get('/oracle/rates', requireAuth: false);
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['success'] != true) return null;

    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;

    final snapshot = parseFxRateSnapshot(data);
    if (!snapshot.isUsable) return null;
    return snapshot;
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
