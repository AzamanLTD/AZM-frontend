// lib/services/presence/beacon_key.dart
// =============================================================================
// AZAMAN — THE ONE CANONICAL BEACON KEY PATH
//
// Every beacon identity in the app is produced and parsed HERE and nowhere
// else. Scanner, controller, gateway and worker screens all call these
// functions, so there is exactly one formatting rule and one validation rule.
// A second inline `'IBEACON:$uuid:$major'` anywhere else is a bug: two
// formatters drift, and a drifted key silently fails to match a candidate.
//
// Format (stable, human-readable, format-tagged):
//   IBEACON:<uuid32>:<major>:<minor>
//   EDDYSTONE_UID:<namespace20>:<instance12>
//
// Normalisation is lossless and idempotent:
//   - the frame tag is upper-case,
//   - UUID is lower-case with hyphens and braces stripped (32 hex chars),
//   - Eddystone namespace/instance are lower-case hex of fixed width,
//   - major/minor are decimal unsigned 16-bit.
//
// `custom` is deliberately NOT supported in this wave — the hardware spike
// has not chosen a broadcast format. Adding it means adding a branch here.
// =============================================================================

import 'presence_models.dart';

/// Thrown when a caller supplies a frame identity that cannot be a real key.
class BeaconKeyException implements Exception {
  final String message;
  const BeaconKeyException(this.message);
  @override
  String toString() => 'BeaconKeyException: $message';
}

const String _kTagIBeacon = 'IBEACON';
const String _kTagEddystoneUid = 'EDDYSTONE_UID';

final RegExp _hex20 = RegExp(r'^[0-9a-f]{20}$');
final RegExp _hex12 = RegExp(r'^[0-9a-f]{12}$');
final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

String _normaliseUuid(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  if (!_hex32.hasMatch(cleaned)) {
    throw BeaconKeyException(
      'iBeacon proximity UUID must be 32 hex chars, got "$raw".',
    );
  }
  return cleaned;
}

int _normaliseUint16(Object? raw, String label) {
  final value = raw is int ? raw : int.tryParse('${raw ?? ''}');
  if (value == null) {
    throw BeaconKeyException('$label must be an integer, got "$raw".');
  }
  if (value < 0 || value > 0xFFFF) {
    throw BeaconKeyException('$label must be 0..65535, got $value.');
  }
  return value;
}

/// Builds the canonical key for an iBeacon frame.
String beaconKeyForIBeacon({
  required String uuid,
  required Object? major,
  required Object? minor,
}) {
  final u = _normaliseUuid(uuid);
  final ma = _normaliseUint16(major, 'major');
  final mi = _normaliseUint16(minor, 'minor');
  return '$_kTagIBeacon:$u:$ma:$mi';
}

/// Builds the canonical key for an Eddystone-UID frame.
String beaconKeyForEddystoneUid({
  required String namespace,
  required String instance,
}) {
  final ns = namespace.trim().toLowerCase();
  final inst = instance.trim().toLowerCase();
  if (!_hex20.hasMatch(ns)) {
    throw BeaconKeyException(
      'Eddystone namespace must be 20 hex chars, got "$namespace".',
    );
  }
  if (!_hex12.hasMatch(inst)) {
    throw BeaconKeyException(
      'Eddystone instance must be 12 hex chars, got "$instance".',
    );
  }
  return '$_kTagEddystoneUid:$ns:$inst';
}

/// Parses and re-canonicalises an existing key string.
///
/// Returns `null` for anything that is not a well-formed key we support —
/// callers treat that as "not a candidate", never as "trust it anyway".
String? canonicalBeaconKey(String? raw) {
  final key = (raw ?? '').trim();
  if (key.isEmpty) return null;
  final parts = key.split(':');
  try {
    switch (parts.first.toUpperCase()) {
      case _kTagIBeacon:
        if (parts.length != 4) return null;
        return beaconKeyForIBeacon(
          uuid: parts[1],
          major: parts[2],
          minor: parts[3],
        );
      case _kTagEddystoneUid:
        if (parts.length != 3) return null;
        return beaconKeyForEddystoneUid(
          namespace: parts[1],
          instance: parts[2],
        );
      default:
        return null;
    }
  } on BeaconKeyException {
    return null;
  }
}

/// True when [raw] is a key this client can canonicalise.
bool isValidBeaconKey(String? raw) => canonicalBeaconKey(raw) != null;

/// The frame family of an already-valid key, or `null`.
BeaconFrameType? beaconFrameTypeOf(String? raw) {
  final key = canonicalBeaconKey(raw);
  if (key == null) return null;
  return key.startsWith('$_kTagIBeacon:')
      ? BeaconFrameType.ibeacon
      : BeaconFrameType.eddystoneUid;
}
