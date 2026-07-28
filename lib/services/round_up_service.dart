// =============================================================================
// AZAMAN — Round-Up Savings Service
//
// Cash App / Acorns-style round-up: every debit transaction rounds up to
// the nearest dollar, and the difference auto-deposits into a
// "Round-Up Vault." This service handles:
//   • Toggle round-up on/off (stored in SharedPreferences for offline-first)
//   • Compute round-up amount for a given transaction
//   • Weekly summary of round-up savings
//
// Reference: Cash App (Boost), Acorns (round-up investing),
//            Monzo (pots with round-up), Chime (automatic round-up)
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';

class RoundUpService {
  static const _keyEnabled = 'round_up_enabled';
  static const _keyTotalSaved = 'round_up_total_saved';
  static const _keyWeeklyHistory = 'round_up_weekly_history';

  /// Get round-up settings
  static Future<RoundUpSettings> getSettings() async {
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
  }

  /// Compute the round-up amount for a transaction.
  /// Rounds up to the nearest $1 (or custom multiple).
  /// Example: $4.30 → round up to $5.00 → save $0.70
  static double computeRoundUp(double amountUsdc, {double roundToMultiple = 1.0}) {
    if (amountUsdc <= 0) return 0;
    final rounded = (amountUsdc / roundToMultiple).ceil() * roundToMultiple;
    final difference = rounded - amountUsdc;
    // Round to 2 decimal places to avoid floating point issues
    return (difference * 100).round() / 100;
  }

  /// Add to total saved (called after each round-up transaction)
  static Future<void> addToTotal(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getDouble(_keyTotalSaved) ?? 0.0;
    await prefs.setDouble(_keyTotalSaved, current + amount);
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

  const RoundUpSettings({
    this.enabled = false,
    this.totalSaved = 0.0,
  });
}
