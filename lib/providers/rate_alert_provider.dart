import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/rate_alert_service.dart';

// =============================================================================
// AZAMAN — RATE ALERT PROVIDER (Phase Q12-FE)
//
// Manages rate alert state: list of alerts, current rate, CRUD operations.
// =============================================================================

class RateAlertNotifier extends ChangeNotifier {
  List<RateAlert> _alerts = [];
  double? _currentRate;
  bool _isLoading = false;
  String? _error;
  bool _hasFetched = false;

  // ── Public getters ──────────────────────────────────────────────────────
  List<RateAlert> get alerts => _alerts;
  List<RateAlert> get activeAlerts =>
      _alerts.where((a) => a.isActive).toList();
  List<RateAlert> get triggeredAlerts =>
      _alerts.where((a) => a.isTriggered).toList();
  double? get currentRate => _currentRate;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasFetched => _hasFetched;

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Fetch alerts from backend. No-op if already fetched unless [force].
  Future<void> fetchAlerts({bool force = false}) async {
    if (_isLoading) return;
    if (!force && _hasFetched) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await rateAlertService.listAlerts();
      _alerts = result.alerts;
      _currentRate = result.currentRate;
      _hasFetched = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('[RateAlertProvider] fetchAlerts error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new alert and prepend to the list on success.
  Future<bool> createAlert({
    required double targetRate,
    required String direction,
    String? note,
  }) async {
    try {
      final alert = await rateAlertService.createAlert(
        targetRate: targetRate,
        direction: direction,
        note: note,
      );
      _alerts.insert(0, alert);
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete an alert by ID and remove from local list.
  Future<bool> deleteAlert(String alertId) async {
    try {
      await rateAlertService.deleteAlert(alertId);
      _alerts.removeWhere((a) => a.id == alertId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Refresh (force re-fetch).
  Future<void> refresh() => fetchAlerts(force: true);
}

/// Riverpod provider
final rateAlertProvider =
    ChangeNotifierProvider<RateAlertNotifier>((ref) {
  return RateAlertNotifier();
});
