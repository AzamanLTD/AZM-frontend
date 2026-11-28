// lib/utils/checkin_scan.dart
// =============================================================================
// What a scanned check-in code is, before it is sent anywhere.
//
// Two signed codes reach the business scanner:
//   • a hotel reservation: {"token":…,"type":"AZAMAN_CHECKIN"}
//   • a transit boarding pass: {"token":…,"type":"AZAMAN_TRANSIT_CHECKIN"}
// A bare token (`<base64url JSON>.<hex signature>`) carries its own `typ` in
// the payload. Reading it here only ROUTES the code to the right endpoint;
// the server verifies the signature, the expiry and every binding, so a
// forged `typ` gains nothing (the wrong endpoint refuses it).
// =============================================================================

import 'dart:convert';

enum CheckInScanKind { reservation, transit }

class CheckInScan {
  const CheckInScan(this.token, this.kind);
  final String token;
  final CheckInScanKind kind;
}

CheckInScan parseCheckInScan(String raw) {
  final value = raw.trim();
  if (value.startsWith('{')) {
    try {
      final payload = jsonDecode(value);
      if (payload is Map) {
        final token = payload['token']?.toString() ?? value;
        final kind = payload['type'] == 'AZAMAN_TRANSIT_CHECKIN'
            ? CheckInScanKind.transit
            : CheckInScanKind.reservation;
        return CheckInScan(token, kind);
      }
    } catch (_) {
      // Not JSON after all: treat as a bare token below.
    }
  }
  return CheckInScan(value, _kindOfBareToken(value));
}

CheckInScanKind _kindOfBareToken(String token) {
  final dot = token.indexOf('.');
  if (dot <= 0) return CheckInScanKind.reservation;
  try {
    final part = token.substring(0, dot);
    final padded = part.padRight((part.length + 3) ~/ 4 * 4, '=');
    final json = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (json is Map && json['typ'] == 'TRANSIT_CHECKIN') {
      return CheckInScanKind.transit;
    }
  } catch (_) {
    // Unreadable payload: let the reservation endpoint refuse it.
  }
  return CheckInScanKind.reservation;
}
