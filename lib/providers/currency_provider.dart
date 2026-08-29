import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

/// The currencies users can choose for displaying balances and conversions.
enum DisplayCurrency { usdc, ghs }

extension DisplayCurrencyX on DisplayCurrency {
  String get code => this == DisplayCurrency.usdc ? 'USDC' : 'GHS';

  static DisplayCurrency fromCode(String? value) {
    return (value ?? '').toUpperCase() == 'GHS'
        ? DisplayCurrency.ghs
        : DisplayCurrency.usdc;
  }
}

/// Server-authoritative FX snapshot. USDC is treated as USD-parity for the
/// current KotaniPay/mock rail, so the backend's USD/GHS rate is the source
/// for USDC/GHS display conversion.
class FxRateSnapshot {
  final double ghsPerUsdc;
  final String source;
  final DateTime? lastSync;
  final DateTime fetchedAt;

  const FxRateSnapshot({
    required this.ghsPerUsdc,
    required this.source,
    required this.lastSync,
    required this.fetchedAt,
  });

  bool get isUsable => ghsPerUsdc > 0;

  double usdcToGhs(double usdc) => usdc * ghsPerUsdc;

  double ghsToUsdc(double ghs) => ghs / ghsPerUsdc;
}

/// Reads the public backend oracle endpoint. This provider deliberately does
/// not invent a fallback FX rate: if the server cannot provide one, callers
/// can keep the primary USDC balance visible without showing a false GHS
/// conversion.
final fxRateProvider = FutureProvider<FxRateSnapshot?>((ref) async {
  try {
    final response = await apiClient.get('/oracle/rates', requireAuth: false);
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['success'] != true) return null;

    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;

    final rate = (data['liveUsdToGhs'] as num?)?.toDouble() ?? 0;
    if (rate <= 0) return null;

    return FxRateSnapshot(
      ghsPerUsdc: rate,
      source: data['rateSource']?.toString() ?? 'UNKNOWN',
      lastSync: DateTime.tryParse(data['lastSync']?.toString() ?? ''),
      fetchedAt: DateTime.now().toUtc(),
    );
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
