// lib/services/presence/presence_models.dart
// =============================================================================
// AZAMAN — NEARBY PRESENCE: TYPED CLIENT CONTRACT (Part 6.6 / packet 4-A)
//
// Pure data. No platform channel, no BLE package, no network call.
//
// FORMAT-AXIS NOTE (deliberate, documented):
// The backend model supports IBEACON, EDDYSTONE_UID and CUSTOM. This client
// enum lists IBEACON and EDDYSTONE_UID only. CUSTOM frames are NOT parsed
// here: the physical compatibility spike has not selected a broadcast format,
// and inventing a custom-frame parser before that spike would bake in a
// hardware assumption we cannot test. The wire contract stays format-agnostic
// (the gateway sends the canonical beacon key string, never a frame struct),
// so adding CUSTOM later is a client enum value plus a key builder branch —
// no schema change on either side.
//
// HONESTY RULE: RSSI is a signal-strength observation, never a distance, a
// floor, or a proof of exact physical location. Nothing in this file derives
// metres, storeys or "you are inside" from an RSSI number.
// =============================================================================

import 'package:flutter/foundation.dart';

/// The broadcast frame families the platform recognises.
///
/// CUSTOM is intentionally absent — see the file header.
enum BeaconFrameType {
  ibeacon,
  eddystoneUid;

  String get wireName => switch (this) {
    BeaconFrameType.ibeacon => 'IBEACON',
    BeaconFrameType.eddystoneUid => 'EDDYSTONE_UID',
  };

  static BeaconFrameType? fromWire(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'IBEACON':
        return BeaconFrameType.ibeacon;
      case 'EDDYSTONE_UID':
        return BeaconFrameType.eddystoneUid;
      default:
        return null;
    }
  }
}

/// A coarse, non-metric signal band.
///
/// These are HINTS for ordering candidates. They are not metres and must not
/// be rendered as a distance ("2 m away") or a storey ("ground floor").
enum ProximityBucket {
  strong('strong'),
  near('near'),
  far('far');

  const ProximityBucket(this.label);
  final String label;
}

/// One observation of one beacon at one instant.
@immutable
class BeaconObservation {
  /// Canonical, stable identity — built by the ONE builder in
  /// `beacon_key.dart`. Never assembled inline anywhere else.
  final String beaconKey;

  final BeaconFrameType frameType;

  /// Smoothed strength in dBm (already averaged by the scanner layer).
  final int rssi;

  /// Bucket derived from [rssi] by the shared configuration.
  final ProximityBucket proximity;

  /// How many raw samples backed this observation. A candidate is not
  /// eligible until this reaches [PresenceTuning.minSamplesPerBeacon].
  final int sampleCount;

  final DateTime observedAt;

  const BeaconObservation({
    required this.beaconKey,
    required this.frameType,
    required this.rssi,
    required this.proximity,
    required this.sampleCount,
    required this.observedAt,
  });

  @override
  String toString() =>
      'BeaconObservation($beaconKey, $rssi dBm, ${proximity.label}, n=$sampleCount)';
}

/// Why a scan was started. The purpose controls whether anything may ever
/// reach the customer presence pipeline.
enum PresenceScanPurpose {
  /// Customer discovery — may produce customer presence events.
  customerDiscovery,

  /// Staff-mode diagnostic — NEVER produces customer presence events.
  workerTest;

  bool get mayEmitCustomerEvents =>
      this == PresenceScanPurpose.customerDiscovery;
}

/// The terminal outcome of one scan attempt.
sealed class PresenceScanOutcome {
  const PresenceScanOutcome();
}

/// Beacons were observed. [observations] is already smoothed and de-duped by
/// beacon key, newest sample wins.
final class ScanFound extends PresenceScanOutcome {
  final List<BeaconObservation> observations;
  const ScanFound(this.observations);
}

/// The scan completed and observed nothing.
final class ScanNone extends PresenceScanOutcome {
  const ScanNone();
}

final class ScanBluetoothOff extends PresenceScanOutcome {
  const ScanBluetoothOff();
}

/// Denied now, but asking again is still meaningful.
final class ScanPermissionDenied extends PresenceScanOutcome {
  const ScanPermissionDenied();
}

/// Denied permanently — the OS will no longer show a prompt. The UI must
/// offer a settings affordance and stay non-blocking.
final class ScanPermissionPermanentlyDenied extends PresenceScanOutcome {
  const ScanPermissionPermanentlyDenied();
}

/// This platform/build cannot scan. Automatic discovery hides; the manual
/// marketplace stays fully available.
final class ScanUnsupported extends PresenceScanOutcome {
  const ScanUnsupported();
}

final class ScanFailed extends PresenceScanOutcome {
  final String reason;
  const ScanFailed(this.reason);
}

// ── Customer preferences ────────────────────────────────────────────────────
//
// All three default OFF and are INDEPENDENT: enabling one never enables
// another. There is no "enable all" path in this file by design.

@immutable
class PresencePreferences {
  /// "Nearby discovery" — may the app look for beacons at all.
  final bool nearbyDiscovery;

  /// Presence notifications — may the app tell the customer about a store.
  final bool presenceNotifications;

  /// Personalisation — may presence inform ranked/contextual surfaces.
  final bool personalisation;

  const PresencePreferences({
    this.nearbyDiscovery = false,
    this.presenceNotifications = false,
    this.personalisation = false,
  });

  static const PresencePreferences allOff = PresencePreferences();

  PresencePreferences copyWith({
    bool? nearbyDiscovery,
    bool? presenceNotifications,
    bool? personalisation,
  }) => PresencePreferences(
    nearbyDiscovery: nearbyDiscovery ?? this.nearbyDiscovery,
    presenceNotifications: presenceNotifications ?? this.presenceNotifications,
    personalisation: personalisation ?? this.personalisation,
  );

  Map<String, dynamic> toJson() => {
    'nearbyDiscovery': nearbyDiscovery,
    'presenceNotifications': presenceNotifications,
    'personalisation': personalisation,
  };

  factory PresencePreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return allOff;
    return PresencePreferences(
      nearbyDiscovery: json['nearbyDiscovery'] == true,
      presenceNotifications: json['presenceNotifications'] == true,
      personalisation: json['personalisation'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PresencePreferences &&
      other.nearbyDiscovery == nearbyDiscovery &&
      other.presenceNotifications == presenceNotifications &&
      other.personalisation == personalisation;

  @override
  int get hashCode =>
      Object.hash(nearbyDiscovery, presenceNotifications, personalisation);
}

/// Human words for a proximity bucket. NEVER a distance, floor or metre
/// estimate — RSSI is not a ranging instrument and this code does not
/// pretend otherwise.
extension ProximityBucketLabel on ProximityBucket {
  String get label => switch (this) {
    ProximityBucket.strong => 'Very close',
    ProximityBucket.near => 'Nearby',
    ProximityBucket.far => 'In the area',
  };
}
