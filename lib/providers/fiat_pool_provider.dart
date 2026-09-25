// lib/providers/fiat_pool_provider.dart
// =============================================================================
// AZAMAN V2 — FIAT POOL STATUS  (Phase B integration)
//
// Backs the "limited local fiat" banner on the withdrawal screen by polling
// the public read-only endpoint:
//
//     GET /api/finance/fiat-pool-status
//     { success, data: { balance, threshold, status, lastUpdate } }
//
// `status` is one of HEALTHY | LIMITED | CRITICAL.
//
// We expose this as a single `FutureProvider` (matching the hand-written
// Riverpod convention used elsewhere in lib/providers/) so any
// ConsumerWidget can simply
//
//     final snapshot = ref.watch(fiatPoolStatusProvider);
//
// and React-style render against `.when(data, loading, error)`. The screen
// can call `ref.invalidate(fiatPoolStatusProvider)` to force a refetch
// (e.g. on pull-to-refresh).
// =============================================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/services/api_client.dart';

/// Coarse-grained classification matching the backend tier model.
enum FiatPoolStatus { healthy, limited, critical, unknown }

FiatPoolStatus _parseFiatPoolStatus(String? raw) {
  switch ((raw ?? '').toUpperCase()) {
    case 'HEALTHY':
      return FiatPoolStatus.healthy;
    case 'LIMITED':
      return FiatPoolStatus.limited;
    case 'CRITICAL':
      return FiatPoolStatus.critical;
    default:
      return FiatPoolStatus.unknown;
  }
}

/// Immutable snapshot returned by the provider.
class FiatPoolSnapshot {
  final double balance;
  final double threshold;
  final FiatPoolStatus status;
  final DateTime? lastUpdate;

  const FiatPoolSnapshot({
    required this.balance,
    required this.threshold,
    required this.status,
    this.lastUpdate,
  });

  /// True when the UI should render a degraded-state warning banner.
  bool get isLimited =>
      status == FiatPoolStatus.limited || status == FiatPoolStatus.critical;

  /// User-facing copy for the warning banner. Empty string in healthy/unknown
  /// states (the screen suppresses the banner entirely in those cases).
  String get bannerMessage {
    switch (status) {
      case FiatPoolStatus.critical:
        return 'Local fiat reserves are critically low right now. '
            'Withdrawals may fail — if yours does, please retry within an hour.';
      case FiatPoolStatus.limited:
        return 'Limited local fiat withdrawals at this time. '
            'If it fails, try again within an hour.';
      case FiatPoolStatus.healthy:
      case FiatPoolStatus.unknown:
        return '';
    }
  }

  static const FiatPoolSnapshot unknown = FiatPoolSnapshot(
    balance: 0,
    threshold: 0,
    status: FiatPoolStatus.unknown,
  );
}

/// Public, no-auth FutureProvider that pulls the live pool status.
///
/// Failures (network, non-2xx, malformed body) collapse silently into
/// `FiatPoolSnapshot.unknown` so the withdrawal screen never gates the user
/// out on a backend hiccup — the banner simply won't render.
final fiatPoolStatusProvider =
    FutureProvider<FiatPoolSnapshot>((ref) async {
  try {
    final response = await apiClient.get(
      '/finance/fiat-pool-status',
      requireAuth: false,
    );

    if (response.statusCode != 200) {
      return FiatPoolSnapshot.unknown;
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return FiatPoolSnapshot.unknown;

    final data = body['data'];
    if (data is! Map<String, dynamic>) return FiatPoolSnapshot.unknown;

    return FiatPoolSnapshot(
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      threshold: (data['threshold'] as num?)?.toDouble() ?? 0.0,
      status: _parseFiatPoolStatus(data['status'] as String?),
      lastUpdate: data['lastUpdate'] != null
          ? DateTime.tryParse(data['lastUpdate'].toString())
          : null,
    );
  } catch (_) {
    return FiatPoolSnapshot.unknown;
  }
});
