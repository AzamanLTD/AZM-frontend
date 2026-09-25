// lib/services/platform_config_service.dart
// =============================================================================
// AZAMAN V2 — PLATFORM CONFIG SERVICE  (Phase ADMIN-CONTROL-2-FE)
//
// Fetches live fee rates from GET /api/auth/platform/config (public,
// no-auth endpoint). Returns a typed [PlatformConfig] value object.
// Falls back to hardcoded defaults on any network error so the app
// is never broken by a missing DB row or server hiccup.
//
// Usage:
//   final config = ref.watch(platformConfigProvider);
//   final fee = config.fiatWithdrawalFeePct; // e.g. 0.02
// =============================================================================

import 'dart:convert';
import 'package:azaman/services/api_client.dart';

// ── Value object ─────────────────────────────────────────────────────────────

class PlatformConfig {
  final double fiatWithdrawalFeePct;
  final double cryptoPlatformFeePct;
  final double cryptoWithdrawalFeePct;
  final double p2pFeePct;
  final double tierThreshold;
  final double vendorShareUnder1k;
  final double vendorShareOver1k;
  final double bankMargin;
  final double thirdPartyMargin;
  final double susuProfitPct;

  const PlatformConfig({
    this.fiatWithdrawalFeePct  = 0.02,
    this.cryptoPlatformFeePct  = 0.00,
    this.cryptoWithdrawalFeePct = 0.01,
    this.p2pFeePct             = 0.02,
    this.tierThreshold         = 1000,
    this.vendorShareUnder1k    = 0.40,
    this.vendorShareOver1k     = 0.50,
    this.bankMargin            = 0.03,
    this.thirdPartyMargin      = 0.02,
    this.susuProfitPct         = 0.03,
  });

  /// Hardcoded safe defaults — used before first fetch and on any failure.
  static const PlatformConfig defaults = PlatformConfig();

  /// Parse from the backend's /api/auth/platform/config response body.
  factory PlatformConfig.fromJson(Map<String, dynamic> json) {
    double s(String key, double fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return PlatformConfig(
      fiatWithdrawalFeePct:   s('fiatWithdrawalFeePct',  0.02),
      cryptoPlatformFeePct:   s('cryptoPlatformFeePct',  0.00),
      cryptoWithdrawalFeePct: s('cryptoWithdrawalFeePct', 0.01),
      p2pFeePct:              s('p2pFeePct',             0.02),
      tierThreshold:          s('tierThreshold',         1000),
      vendorShareUnder1k:     s('vendorShareUnder1k',    0.40),
      vendorShareOver1k:      s('vendorShareOver1k',     0.50),
      bankMargin:             s('bankMargin',            0.03),
      thirdPartyMargin:       s('thirdPartyMargin',      0.02),
      susuProfitPct:          s('susuProfitPct',         0.03),
    );
  }

  @override
  String toString() =>
      'PlatformConfig(fiatFee=$fiatWithdrawalFeePct, '
      'cryptoFee=$cryptoWithdrawalFeePct, '
      'p2p=$p2pFeePct, '
      'tier=$tierThreshold, '
      'vendorSplitUnder=$vendorShareUnder1k, '
      'vendorSplitOver=$vendorShareOver1k)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class PlatformConfigService {
  /// Fetches live config from the backend.
  /// Returns [PlatformConfig.defaults] on any error — non-fatal by design.
  Future<PlatformConfig> fetch() async {
    try {
      // No auth required — public endpoint (generalLimiter protected)
      final response = await apiClient.get(
        '/auth/platform/config',
        requireAuth: false,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true && body['config'] is Map<String, dynamic>) {
          return PlatformConfig.fromJson(
            body['config'] as Map<String, dynamic>,
          );
        }
      }
    } catch (e) {
      // Non-fatal: network error, server offline, parse failure — all fall
      // through to defaults so the app continues to work normally.
      debugLog('[PlatformConfigService] fetch failed (using defaults): $e');
    }
    return PlatformConfig.defaults;
  }
}

// ── Debug helper (avoids importing dart:developer everywhere) ─────────────────
void debugLog(String msg) {
  // ignore: avoid_print
  assert(() { print(msg); return true; }());
}
