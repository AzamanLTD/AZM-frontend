import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/services/vendor_analytics_service.dart';

// =============================================================================
// AZAMAN — VENDOR ANALYTICS PROVIDER (Phase Q16-FE)
//
// Riverpod ChangeNotifier managing:
//   - Active period selection (7d / 30d / 90d)
//   - Loading / error / data states
//   - Fetch + refresh + period switch
// =============================================================================

enum AnalyticsPeriod {
  sevenDays('7d', '7D'),
  thirtyDays('30d', '30D'),
  ninetyDays('90d', '90D');

  final String queryValue;
  final String displayLabel;

  const AnalyticsPeriod(this.queryValue, this.displayLabel);
}

class VendorAnalyticsNotifier extends ChangeNotifier {
  VendorAnalyticsData? _data;
  AnalyticsPeriod _activePeriod = AnalyticsPeriod.sevenDays;
  bool _isLoading = false;
  String? _error;
  bool _hasFetched = false;

  // ── Public getters ──────────────────────────────────────────────────────
  VendorAnalyticsData? get data => _data;
  AnalyticsPeriod get activePeriod => _activePeriod;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasFetched => _hasFetched;

  // ── Convenience getters ─────────────────────────────────────────────────
  VendorAnalyticsSummary? get summary => _data?.summary;
  List<VolumeDataPoint> get volumeTimeline => _data?.volumeTimeline ?? [];
  List<MethodBreakdownEntry> get methodBreakdown => _data?.methodBreakdown ?? [];

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Fetch analytics for the current active period.
  /// If [force] is false and data is already loaded for the same period, no-op.
  Future<void> fetchAnalytics({bool force = false}) async {
    if (_isLoading) return;
    if (!force && _hasFetched && _data != null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await vendorAnalyticsService.fetchAnalytics(
        _activePeriod.queryValue,
      );
      _data = result;
      _hasFetched = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('[VendorAnalyticsProvider] fetch error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switch period and re-fetch.
  Future<void> switchPeriod(AnalyticsPeriod period) async {
    if (period == _activePeriod && _hasFetched) return;
    _activePeriod = period;
    _hasFetched = false;
    notifyListeners();
    await fetchAnalytics(force: true);
  }

  /// Pull-to-refresh: force re-fetch for the current period.
  Future<void> refresh() async {
    await fetchAnalytics(force: true);
  }
}

/// Riverpod provider
final vendorAnalyticsProvider =
    ChangeNotifierProvider.autoDispose<VendorAnalyticsNotifier>((ref) {
  return VendorAnalyticsNotifier();
});
