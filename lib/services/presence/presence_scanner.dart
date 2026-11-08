// lib/services/presence/presence_scanner.dart
// =============================================================================
// AZAMAN — PRESENCE SCANNER SEAM
//
// Mirrors the existing NearbyLocationResolver pattern: an abstract seam, one
// real implementation, one scripted fake. The real one is a STUB in this wave
// and returns ScanUnsupported — see the honesty note below.
//
// HONESTY NOTE (non-negotiable):
// `PlatformPresenceScanner` returns ScanUnsupported because no BLE scanning
// package is wired and the physical compatibility spike has not selected a
// broadcast format. A fake scan proves the CLIENT flow — state machine,
// privacy gates, throttle, UI — and proves NOTHING about real beacon
// compatibility, range, or which frame family a given venue broadcasts.
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'beacon_key.dart';
import 'presence_config.dart';
import 'presence_models.dart';

/// The scanning seam. Implementations own platform interaction only; the
/// controller owns state, throttling and eligibility.
abstract class PresenceScanner {
  const PresenceScanner();

  /// Runs ONE scan window and settles to a terminal outcome.
  ///
  /// Implementations must not throw for expected conditions (Bluetooth off,
  /// permission states, unsupported hardware) — those are outcomes, not
  /// errors. [timeout] bounds the listen window.
  Future<PresenceScanOutcome> scan({
    required PresenceScanPurpose purpose,
    required PresenceTuning tuning,
  });

  /// Releases any platform resources. Safe to call repeatedly.
  Future<void> dispose();
}

/// The real scanner. NOT IMPLEMENTED in this wave — always Unsupported.
class PlatformPresenceScanner implements PresenceScanner {
  const PlatformPresenceScanner();

  @override
  Future<PresenceScanOutcome> scan({
    required PresenceScanPurpose purpose,
    required PresenceTuning tuning,
  }) async => const ScanUnsupported();

  @override
  Future<void> dispose() async {}
}

/// Deterministic scripted scenarios. No delays, no Bluetooth, no clocks.
enum FakePresenceScenario {
  foundOne,
  foundMany,
  none,
  bluetoothOff,
  permissionDenied,
  permissionPermanentlyDenied,
  unsupported,
  failed,

  /// A scan that never settles by itself — the test completes it later,
  /// which is how the stale-result race is driven.
  manual,
}

/// Test double. Switch [scenario] freely; each scan resolves immediately
/// except [FakePresenceScenario.manual].
class FakePresenceScanner implements PresenceScanner {
  FakePresenceScanner({
    this.scenario = FakePresenceScenario.foundOne,
    this.observations,
  });

  FakePresenceScenario scenario;
  List<BeaconObservation>? observations;

  /// Number of scan() calls, for throttle assertions.
  int scanCount = 0;

  /// Purposes seen, in order — proves a worker test never scanned as customer.
  final List<PresenceScanPurpose> scannedPurposes = <PresenceScanPurpose>[];

  final List<Completer<PresenceScanOutcome>> _pending =
      <Completer<PresenceScanOutcome>>[];

  bool _disposed = false;

  /// How many manual scans are currently awaiting completion.
  int get pendingCount => _pending.where((c) => !c.isCompleted).length;

  @override
  Future<PresenceScanOutcome> scan({
    required PresenceScanPurpose purpose,
    required PresenceTuning tuning,
  }) {
    scanCount += 1;
    scannedPurposes.add(purpose);
    if (_disposed) {
      return Future<PresenceScanOutcome>.value(
        const ScanFailed('scanner disposed'),
      );
    }

    switch (scenario) {
      case FakePresenceScenario.foundOne:
        return Future<PresenceScanOutcome>.value(
          ScanFound(observations ?? defaultFoundOne(tuning)),
        );
      case FakePresenceScenario.foundMany:
        return Future<PresenceScanOutcome>.value(
          ScanFound(observations ?? defaultFoundMany(tuning)),
        );
      case FakePresenceScenario.none:
        return Future<PresenceScanOutcome>.value(const ScanNone());
      case FakePresenceScenario.bluetoothOff:
        return Future<PresenceScanOutcome>.value(const ScanBluetoothOff());
      case FakePresenceScenario.permissionDenied:
        return Future<PresenceScanOutcome>.value(const ScanPermissionDenied());
      case FakePresenceScenario.permissionPermanentlyDenied:
        return Future<PresenceScanOutcome>.value(
          const ScanPermissionPermanentlyDenied(),
        );
      case FakePresenceScenario.unsupported:
        return Future<PresenceScanOutcome>.value(const ScanUnsupported());
      case FakePresenceScenario.failed:
        return Future<PresenceScanOutcome>.value(
          const ScanFailed('simulated radio failure'),
        );
      case FakePresenceScenario.manual:
        final completer = Completer<PresenceScanOutcome>();
        _pending.add(completer);
        return completer.future;
    }
  }

  /// Completes the [index]-th manual scan (0-based, in start order).
  void completeManual(int index, PresenceScanOutcome outcome) {
    final completer = _pending[index];
    if (!completer.isCompleted) completer.complete(outcome);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final c in _pending) {
      if (!c.isCompleted) c.complete(const ScanFailed('scanner disposed'));
    }
  }

  // ── Canonical fixtures ──────────────────────────────────────────────────
  //
  // Built through the ONE key builder, so a fixture can never encode a key
  // shape the parser would reject.

  static BeaconObservation observation({
    required String beaconKey,
    required int rssi,
    BeaconFrameType? frameType,
    int sampleCount = 3,
    DateTime? at,
    PresenceTuning tuning = PresenceTuning.standard,
  }) => BeaconObservation(
    beaconKey: canonicalBeaconKey(beaconKey) ?? beaconKey,
    frameType:
        frameType ?? beaconFrameTypeOf(beaconKey) ?? BeaconFrameType.ibeacon,
    rssi: rssi,
    proximity: tuning.bucketFor(rssi),
    sampleCount: sampleCount,
    observedAt: at ?? DateTime.utc(2026, 1, 1, 12),
  );

  static String keyIBeacon(String uuid, int major, int minor) =>
      beaconKeyForIBeacon(uuid: uuid, major: major, minor: minor);

  static List<BeaconObservation> defaultFoundOne(PresenceTuning tuning) => [
    observation(
      beaconKey: keyIBeacon('f7826da64fa24e988024bc5b71e0893e', 1, 101),
      rssi: -58,
      tuning: tuning,
    ),
  ];

  static List<BeaconObservation> defaultFoundMany(PresenceTuning tuning) => [
    observation(
      beaconKey: keyIBeacon('f7826da64fa24e988024bc5b71e0893e', 1, 101),
      rssi: -57,
      tuning: tuning,
    ),
    observation(
      beaconKey: keyIBeacon('f7826da64fa24e988024bc5b71e0893e', 1, 102),
      rssi: -72,
      tuning: tuning,
    ),
    observation(
      beaconKey: keyIBeacon('f7826da64fa24e988024bc5b71e0893e', 2, 205),
      rssi: -86,
      tuning: tuning,
    ),
  ];
}

/// Overridable so tests and the demo can inject a fake without touching the
/// production build. Defaults to the honest stub.
final presenceScannerProvider = Provider<PresenceScanner>((ref) {
  return const PlatformPresenceScanner();
});
