// =============================================================================
// AZAMAN — HOME SUMMARY PROVIDER  (Phase G)
//
// Riverpod surface for the aggregated home-screen snapshot. Wraps
// HomeSummaryService.fetch() in a StateNotifier so widgets can:
//
//   * `ref.watch(homeSummaryProvider)`        — reactive snapshot
//   * `ref.read(homeSummaryProvider.notifier).refresh()` — pull-to-refresh
//
// First mount triggers an immediate background fetch so the home renders
// real data without the user having to swipe down. Subsequent refreshes
// keep the previous snapshot visible while the request is in-flight (only
// `loading` flips), so the UI doesn't blink to placeholders.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/services/home_summary_service.dart';
import 'package:azaman/widgets/live_market_section.dart'
    show rateHistoryProvider, RateObservation;

class HomeSummaryNotifier extends StateNotifier<HomeSummary> {
  final Ref _ref;
  final HomeSummaryService _service;
  bool _firstFetchKicked = false;

  HomeSummaryNotifier(this._ref, this._service) : super(HomeSummary.empty);

  /// Triggered on first widget mount so the home page paints real data
  /// without waiting for the user to pull-to-refresh. Idempotent — the
  /// flag prevents duplicate fetches during the initial paint storm.
  void primeIfNeeded() {
    if (_firstFetchKicked) return;
    _firstFetchKicked = true;
    // Schedule via microtask so we don't block the first frame and so
    // ref.read() of dependent providers happens after their construction.
    Future.microtask(refresh);
  }

  /// Re-fetches every section in parallel. Keeps the previous snapshot
  /// visible while loading so the UI doesn't blink — only `loading` flips.
  Future<void> refresh() async {
    if (state.loading) return;
    state = state.copyWith(loading: true);

    try {
      final auth = _ref.read(authProvider);
      final userId = auth.user?.id;
      final fresh = await _service.fetch(currentUserId: userId);
      if (!mounted) return;
      state = fresh;
      // Phase H review pass: append the new oracle rate to the rolling
      // sparkline window from HERE (the notifier) — appending from inside
      // LiveMarketSection.build mutated a StateProvider mid-build, which
      // trips Riverpod debug asserts and produces a frame of flicker.
      // Idempotent: skip identical rates and skip when oracle is dark (0).
      if (fresh.rates.isAvailable) {
        final rate = fresh.rates.retailRate;
        final list = _ref.read(rateHistoryProvider);
        final isDuplicate = list.isNotEmpty &&
            (list.last.rate - rate).abs() < 0.0001;
        if (!isDuplicate) {
          final next = [...list, RateObservation(DateTime.now(), rate)];
          if (next.length > 24) next.removeAt(0);
          _ref.read(rateHistoryProvider.notifier).state = next;
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[HomeSummary] refresh failed: $e\n$st');
      }
      if (!mounted) return;
      // Service.fetch already swallows per-section errors, so a top-level
      // throw is a programming error. Surface it as a global "everything
      // failed" snapshot rather than crashing the home screen.
      state = HomeSummary.empty.copyWith(loading: false);
    }
  }
}

/// Public Riverpod handle.
///
/// In any ConsumerWidget:
///   final s = ref.watch(homeSummaryProvider);
///   ref.read(homeSummaryProvider.notifier).refresh();
final homeSummaryProvider =
    StateNotifierProvider<HomeSummaryNotifier, HomeSummary>((ref) {
  return HomeSummaryNotifier(ref, HomeSummaryService());
});
