// lib/services/nearby_location_tracker.dart
// =============================================================================
// AZAMAN — NEARBY LOCATION TRACKER (Programme G3)
//
// Foreground-ONLY position stream for the Near You proximity surface.
//
// Contract (each point is load-bearing — G3 of the marketplace programme):
//   1. FOREGROUND-ONLY. The stream starts only when an explicit consumer
//      asked for proximity updates AND the app is in the foreground, and it
//      is stopped when either condition ends (Near You off, surface exit,
//      app paused). Android runs it as a foreground service with a visible
//      notification via ForegroundNotificationConfig — the ONLY sanctioned
//      location mode in this app. No background location is ever requested
//      or received, and iOS background updates stay disabled.
//   2. SIGNIFICANT MOVES ONLY. 100 m distanceFilter + 30 s interval cap:
//      each event means the user actually moved, so each event can honestly
//      re-fire the nearby search.
//   3. STALE-EVENT GUARD. [stop] bumps the generation, so a position that
//      lands after the tracker stopped (or after a restart created a newer
//      subscription) is DROPPED — a position from an exited surface can
//      never re-fire a nearby search or resurrect the old feed.
//   4. TESTABLE. The platform stream is injected ([streamFactory]); tests
//      feed synthetic streams and assert the guard semantics without
//      touching platform channels.
// =============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

/// Builds the platform position stream for the given settings. Injectable so
/// tests can drive [NearbyLocationTracker] with synthetic positions.
typedef PositionStreamFactory =
    Stream<Position> Function(LocationSettings settings);

/// Foreground-only significant-move position tracker for the Near You
/// surface. See the file header for the full contract.
class NearbyLocationTracker {
  NearbyLocationTracker({
    PositionStreamFactory? streamFactory,
    void Function(Position position)? onPosition,
  }) : _streamFactory =
           streamFactory ?? _platformPositionStream,
       _onPosition = onPosition;

  final PositionStreamFactory _streamFactory;
  final void Function(Position position)? _onPosition;

  StreamSubscription<Position>? _subscription;

  /// Generation armed at [start] and re-armed at [stop]: an event is
  /// delivered only while `_active` AND its subscription generation is
  /// still the current one.
  int _generation = 0;
  bool _active = false;

  /// Whether the tracker currently owns a live (started, not stopped)
  /// position stream.
  bool get isRunning => _active;

  /// Starts the foreground-only stream.
  ///
  /// Idempotent: calling [start] while running is a no-op — no duplicate
  /// subscriptions, no notification churn, no duplicate nearby fires.
  void start() {
    if (_active) return;
    _active = true;
    final generation = ++_generation;
    try {
      _subscription = _streamFactory(_settingsForPlatform).listen(
        (position) {
          if (!_active || generation != _generation) return; // stale — drop
          _onPosition?.call(position);
        },
        onError: (_) {
          // The platform stream itself failed (services disabled mid-
          // stream, channel unavailable, permission revoked). Stop
          // cleanly — a dead stream must never pretend to be live. The
          // surface renders its own honest location-unavailable state.
          if (generation == _generation) stop();
        },
      );
    } catch (_) {
      // The factory itself threw (no location platform at all).
      _active = false;
      _generation++;
    }
  }

  /// Stops the stream and arms the stale-event guard: any event already in
  /// flight from the cancelled subscription is dropped on arrival.
  void stop() {
    if (!_active && _subscription == null) return;
    _active = false;
    // Re-arm so the in-flight event from the subscription being cancelled
    // fails its generation check when it lands.
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Permanent teardown — identical to [stop] (kept for symmetry with the
  /// screen's dispose lifecycle).
  void dispose() => stop();

  // ── Platform settings ──────────────────────────────────────────────────────

  /// FOREGROUND-ONLY settings per platform:
  /// • Android — the stream runs as a foreground service with a visible
  ///   notification (the sanctioned way to keep a stream alive while the
  ///   app is open); no background execution is requested.
  /// • iOS — background location updates stay explicitly disabled and the
  ///   background indicator is not shown.
  /// • Other platforms — the plain distance/accuracy settings.
  static LocationSettings get _settingsForPlatform {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Azaman — finding businesses near you',
          notificationText:
              'Location updates run only while Marketplace is open.',
          notificationChannelName: 'Near You location',
          enableWakeLock: false,
          enableWifiLock: false,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 100,
    );
  }

  static Stream<Position> _platformPositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
}
