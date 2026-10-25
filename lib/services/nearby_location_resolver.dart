// lib/services/nearby_location_resolver.dart
// =============================================================================
// AZAMAN — NEARBY LOCATION RESOLVER (Programme G2/G3)
//
// One-shot location resolution for the Near You surface: check services,
// ask permission in context, return the current position — or throw.
//
// Why a separate injectable class: the geolocator platform calls are
// futures that hang forever in widget tests (no platform channels), so
// the screen's resolve state machine must be drivable with a fake
// resolver. The screen keeps the STATE (resolving / failure / position);
// this class owns only the platform interaction.
// =============================================================================

import 'package:geolocator/geolocator.dart';

/// Resolves the device's current position for the Near You surface.
///
/// Throws when location services are off or permission is denied — the
/// screen renders its own honest location-unavailable state from that.
abstract class NearbyLocationResolver {
  const NearbyLocationResolver();

  /// Check services, ask permission (in context) when needed, and return
  /// the current position.
  Future<Position> resolve();

  /// Workstream H — the NO-PROMPT seam. Returns a position ONLY when
  /// location services are on AND permission is ALREADY granted. It
  /// never requests anything: a silent capability probe. Callers use it
  /// to co-activate proximity features opportunistically (e.g. pressing
  /// Mix) without ever surfacing a permission ask the user did not
  /// initiate. Unavailable → throws; the caller keeps its honest off
  /// state and its explicit request/retry route.
  Future<Position> resolveSilently();
}

/// The real platform resolver: the geolocator permission dance.
class PlatformNearbyLocationResolver extends NearbyLocationResolver {
  const PlatformNearbyLocationResolver();

  @override
  Future<Position> resolve() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // The EXPLICIT path (the user pressed Near You) asks in context.
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission denied.';
    }
    return Geolocator.getCurrentPosition();
  }

  @override
  Future<Position> resolveSilently() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled.';
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission not granted.';
    }
    return Geolocator.getCurrentPosition();
  }
}

/// Test resolver: fails immediately, as a device with location off would.
class FailingNearbyLocationResolver extends NearbyLocationResolver {
  const FailingNearbyLocationResolver();

  @override
  Future<Position> resolve() async {
    throw 'Location services are disabled.';
  }

  @override
  Future<Position> resolveSilently() async {
    throw 'Location services are disabled.';
  }
}
