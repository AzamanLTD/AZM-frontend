// lib/services/presence/presence_config.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE: ONE SHARED TUNING OBJECT
//
// RSSI bucketing, smoothing and the scan budget live in exactly ONE place so
// the scanner, the controller and the tests cannot disagree about what
// "strong" means or how often a scan may start.
//
// The bucket thresholds are signal-strength bands, NOT distance. A -60 dBm
// reading does not mean "3 metres". The UI renders "strong / near / far"
// hints only, which is why these are named buckets and not metres.
// =============================================================================

import 'presence_models.dart';

class PresenceTuning {
  const PresenceTuning({
    this.strongAtOrAboveDbm = -65,
    this.nearAtOrAboveDbm = -80,
    this.scanWindow = const Duration(seconds: 4),
    this.minScanInterval = const Duration(seconds: 20),
    this.windowForRateLimit = const Duration(seconds: 30),
    this.maxStartsPerWindow = 4,
    this.minSamplesPerBeacon = 2,
    this.smoothingWindow = 5,
  });

  /// dBm at or above which an observation is "strong".
  final int strongAtOrAboveDbm;

  /// dBm at or above which an observation is "near" (below strong).
  final int nearAtOrAboveDbm;

  /// How long one scan listens before settling.
  final Duration scanWindow;

  /// Minimum gap between scan starts (product rule: 20 s).
  final Duration minScanInterval;

  /// Rate-limit window (product rule: max 4 starts in 30 s).
  final Duration windowForRateLimit;
  final int maxStartsPerWindow;

  /// A beacon is not eligible as a candidate until it has this many samples.
  /// One stray packet is not evidence that a store is in front of you.
  final int minSamplesPerBeacon;

  /// Rolling average depth for RSSI smoothing.
  final int smoothingWindow;

  ProximityBucket bucketFor(int rssiDbm) {
    if (rssiDbm >= strongAtOrAboveDbm) return ProximityBucket.strong;
    if (rssiDbm >= nearAtOrAboveDbm) return ProximityBucket.near;
    return ProximityBucket.far;
  }

  /// Shared instance. Tests may construct their own with shorter windows, but
  /// production code reads this one.
  static const PresenceTuning standard = PresenceTuning();

  /// Compressed budget for widget/unit tests that drive the real controller
  /// timing rules without waiting seconds. Never used in production wiring.
  static const PresenceTuning fast = PresenceTuning(
    scanWindow: Duration(milliseconds: 40),
    minScanInterval: Duration(milliseconds: 40),
    windowForRateLimit: Duration(milliseconds: 200),
  );
}
