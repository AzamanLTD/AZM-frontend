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
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission denied.';
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
}
