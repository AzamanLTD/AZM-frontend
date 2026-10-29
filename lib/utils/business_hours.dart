// =============================================================================
// AZAMAN — BUSINESS HOURS (pure, clock-injected)
//
// The ONLY place in the app that understands `BusinessLocation.operatingHours`
// (`{mon: "8:00-22:00", ...}`). Cards, world deck, local pulse and the store
// info strip all call `business.openStateAt(now)` — nobody reads the raw map.
// `businessMeta` never carried hours and must not be consulted.
// =============================================================================

import 'package:azaman/models/business_models.dart';

enum OpenState { open, closed, unknown }

abstract final class BusinessHours {
  /// Same key mapping as the legacy `_isOpenNow` (Sunday = 0).
  static const List<String> dayKeys = [
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
  ];

  /// A business is open if ANY of its locations is open right now.
  /// `unknown` when no location carries parseable hours for today.
  static OpenState stateAt(List<BusinessLocation> locations, DateTime now) {
    var sawHours = false;
    final key = dayKeys[now.weekday % 7];
    for (final loc in locations) {
      final hours = loc.operatingHours;
      if (hours == null || hours.isEmpty) continue;
      final s = stateOfRange(hours[key]?.toString(), now);
      if (s == OpenState.unknown) continue;
      sawHours = true;
      if (s == OpenState.open) return OpenState.open;
    }
    return sawHours ? OpenState.closed : OpenState.unknown;
  }

  /// Parses one `"HH:mm-HH:mm"` window (hour may be 1 or 2 digits, as the
  /// data has `8:00-22:00`). Overnight windows (`20:00-02:00`) are honoured.
  static OpenState stateOfRange(String? range, DateTime now) {
    if (range == null) return OpenState.unknown;
    final parts = range.split('-');
    if (parts.length != 2) return OpenState.unknown;
    final open = _minutes(parts[0].trim());
    final close = _minutes(parts[1].trim());
    if (open == null || close == null) return OpenState.unknown;
    final nowMins = now.hour * 60 + now.minute;
    final inWindow = close < open
        ? (nowMins >= open || nowMins < close) // crosses midnight
        : (nowMins >= open && nowMins < close);
    return inWindow ? OpenState.open : OpenState.closed;
  }

  static int? _minutes(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    if (h > 24 || mm > 59) return null;
    return h * 60 + mm;
  }
}

extension BusinessOpenState on BusinessProfile {
  OpenState openStateAt(DateTime now) => BusinessHours.stateAt(locations, now);
}