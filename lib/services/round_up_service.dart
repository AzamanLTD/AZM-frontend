// =============================================================================
// AZAMAN — Round-Up Savings Service (Phase 3)
//
// Cash App / Acorns-style: every debit transaction rounds up to the nearest
// dollar, and the difference auto-deposits into a "Round-Up Vault."
//
// Now backed by /api/round-up — settings persist server-side and
// round-ups deposit into real vaults.
//
// Reference: Cash App (Boost), Acorns (round-up investing),
//            Monzo (pots with round-up), Chime (automatic round-up)
// =============================================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:azaman/services/api_client.dart';

class RoundUpService {
  static const _keyEnabled = 'round_up_enabled';
  static const _keyTotalSaved = 'round_up_total_saved';

  /// Get round-up settings from backend
  static Future<RoundUpSettings> getSettings() async {
    try {
      final res = await apiClient.get('/round-up');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final settings = body['settings'] as Map<String, dynamic>;
        // Cache locally for offline access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyEnabled, settings['enabled'] ?? false);
        await prefs.setDouble(_keyTotalSaved, (settings['totalSavedUsdc'] ?? 0).toDouble());
        return RoundUpSettings(
          enabled: settings['enabled'] ?? false,
          totalSaved: (settings['totalSavedUsdc'] ?? 0).toDouble(),
          targetVaultId: settings['targetVaultId'],
          multiplier: (settings['multiplier'] ?? 1.0).toDouble(),
        );
      }
    } catch (_) {}
    // Fallback to cached
    final prefs = await SharedPreferences.getInstance();
    return RoundUpSettings(
      enabled: prefs.getBool(_keyEnabled) ?? false,
      totalSaved: prefs.getDouble(_keyTotalSaved) ?? 0.0,
    );
  }

  /// Enable/disable round-up
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
    try {
      await apiClient.put('/round-up', {'enabled': enabled});
    } catch (_) {}
  }

  /// Update settings (target vault, multiplier)
  static Future<void> updateSettings({
    bool? enabled,
    String? targetVaultId,
    double? multiplier,
  }) async {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (targetVaultId != null) body['targetVaultId'] = targetVaultId;
    if (multiplier != null) body['multiplier'] = multiplier;
    try {
      await apiClient.put('/round-up', body);
    } catch (_) {}
  }

  /// Compute the round-up amount for a transaction.
  /// Rounds up to the nearest $1 (or custom multiple).
  /// Example: $4.30 → round up to $5.00 → save $0.70
  static double computeRoundUp(double amountUsdc, {double roundToMultiple = 1.0}) {
    if (amountUsdc <= 0) return 0;
    final rounded = (amountUsdc / roundToMultiple).ceil() * roundToMultiple;
    final difference = rounded - amountUsdc;
    return (difference * 100).round() / 100;
  }

  /// Process a round-up for a transaction (server-side deposits into vault)
  static Future<double> processRoundUp(double amountUsdc) async {
    try {
      final res = await apiClient.post('/round-up/process', {'amountUsdc': amountUsdc});
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final roundUp = (body['roundUpAmount'] ?? 0).toDouble();
        final total = (body['totalSaved'] ?? 0).toDouble();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_keyTotalSaved, total);
        return roundUp;
      }
    } catch (_) {}
    return 0;
  }

  /// Get total saved amount
  static Future<double> getTotalSaved() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyTotalSaved) ?? 0.0;
  }
}

// ── Settings value object ────────────────────────────────────────────────────

class RoundUpSettings {
  final bool enabled;
  final double totalSaved;
  final String? targetVaultId;
  final double multiplier;

  const RoundUpSettings({
    this.enabled = false,
    this.totalSaved = 0.0,
    this.targetVaultId,
    this.multiplier = 1.0,
  });
}
