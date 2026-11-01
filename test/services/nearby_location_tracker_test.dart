import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:azaman/services/nearby_location_tracker.dart';

/// G3 — the FOREGROUND-ONLY nearby location stream. The platform stream is
/// injected, so these tests prove the contract without platform channels:
///   • start() is idempotent (no duplicate subscriptions);
///   • stop() drops every late event — a position from an exited surface
///     can never re-fire anything;
///   • restart() creates a fresh generation — an event from the cancelled
///     subscription dies even if it lands after the restart;
///   • every delivered event passed the guards and reached onPosition.

Position _pos(double lat) => Position(
  longitude: -0.19,
  latitude: lat,
  timestamp: DateTime.now(),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test('delivers live events to onPosition', () async {
    final controller = StreamController<Position>();
    final received = <Position>[];
    final tracker = NearbyLocationTracker(
      streamFactory: (_) => controller.stream,
      onPosition: received.add,
    );

    tracker.start();
    controller.add(_pos(5.6));
    await Future<void>.delayed(Duration.zero);

    expect(received.length, 1);
    tracker.dispose();
    await controller.close();
  });

  test(
    'start() is idempotent — no duplicate subscription, no dup events',
    () async {
      final controller = StreamController<Position>.broadcast();
      var factoryCalls = 0;
      final received = <Position>[];
      final tracker = NearbyLocationTracker(
        streamFactory: (_) {
          factoryCalls++;
          return controller.stream;
        },
        onPosition: received.add,
      );

      tracker.start();
      tracker.start(); // second call must be a no-op
      controller.add(_pos(5.6));
      await Future<void>.delayed(Duration.zero);

      expect(factoryCalls, 1, reason: 'exactly one platform stream requested');
      expect(received.length, 1, reason: 'one event delivered once');
      tracker.dispose();
      await controller.close();
    },
  );

  test(
    'stop() drops every late event — an exited surface cannot re-fire',
    () async {
      final controller = StreamController<Position>();
      final received = <Position>[];
      final tracker = NearbyLocationTracker(
        streamFactory: (_) => controller.stream,
        onPosition: received.add,
      );

      tracker.start();
      tracker.stop();

      // Position lands after the user left the surface.
      controller.add(_pos(5.6));
      await Future<void>.delayed(Duration.zero);
      controller.add(_pos(5.7));
      await Future<void>.delayed(Duration.zero);

      expect(
        received,
        isEmpty,
        reason: 'positions after stop() must never reach the consumer',
      );
      expect(tracker.isRunning, isFalse);
      await controller.close();
    },
  );

  test('restart() forms a fresh generation — a straggler from the cancelled '
      'subscription dies even after the restart', () async {
    // Broadcast controller lets both the cancelled and the new
    // subscription receive the same event.
    final controller = StreamController<Position>.broadcast();
    final received = <double>[];
    final tracker = NearbyLocationTracker(
      streamFactory: (_) => controller.stream,
      onPosition: (p) => received.add(p.latitude),
    );

    tracker.start();
    // The surface's first (never cancelled — late) subscription still
    // exists… stop() bumps the generation FIRST.
    tracker.stop();
    tracker.start();

    controller.add(_pos(5.6)); // the straggler event, post-restart
    await Future<void>.delayed(Duration.zero);

    // The event is delivered once (the fresh subscription) — not twice,
    // and it must be attributed to the live session.
    expect(received, [5.6]);
    tracker.dispose();
    await controller.close();
  });

  test('an event delivered before any start is impossible — tracker begins '
      'stopped', () {
    final controller = StreamController<Position>.broadcast();
    final received = <Position>[];
    final tracker = NearbyLocationTracker(
      streamFactory: (_) => controller.stream,
      onPosition: received.add,
    );

    expect(tracker.isRunning, isFalse);
    tracker.stop(); // no-op on a fresh tracker
    expect(tracker.isRunning, isFalse);
    tracker.dispose();
  });
}
