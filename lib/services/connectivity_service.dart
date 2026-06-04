// =============================================================================
// AZAMAN — CONNECTIVITY SERVICE  (Phase H4)
//
// Wraps `connectivity_plus` into a Riverpod `StreamProvider<bool>` that emits
// `true` when at least one network interface is up (wifi, mobile, ethernet,
// vpn, bluetooth) and `false` when the device is fully offline.
//
// What this catches
// -----------------
// Radio-state changes only — phone disconnects from wifi, drops onto mobile
// data, enters airplane mode, leaves a tunnel, etc. The banner reacts within
// the OS-reported event (~immediate on iOS, ~1-2s on Android).
//
// What this does NOT catch (deliberate scope)
// -------------------------------------------
// "Wifi connected but the upstream router has no internet" (captive portals,
// home wifi without WAN, corporate wifi behind a login page). Catching that
// requires probing a real endpoint on every state change, which is its own
// concern (battery, cost, privacy, retry-storm risk if the probe target is
// down). If we ever add it, the right place is a follow-up `internet_probe`
// service that combines this radio-state stream with periodic HEAD-pings to
// `${AppConfig.apiUrl}/health` and AND-s the two flags. Out of scope here.
// =============================================================================

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` when at least one network interface is up.
///
/// Defaults to `true` while the first `checkConnectivity()` is in flight so
/// the offline banner doesn't flash on cold launch.
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  final controller = StreamController<bool>();

  bool isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    // ConnectivityResult.none is the "no network" signal. Any other value
    // (wifi / mobile / ethernet / vpn / bluetooth / other) counts as up.
    return results.any((r) => r != ConnectivityResult.none);
  }

  // Initial check — fire-and-forget. The stream's .when() will keep the
  // last-known value even after the first emission.
  unawaited(connectivity.checkConnectivity().then((results) {
    if (controller.isClosed) return;
    controller.add(isOnline(results));
  }).catchError((Object e) {
    if (kDebugMode) debugPrint('[Connectivity] initial check failed: $e');
    if (!controller.isClosed) controller.add(true); // Fail open.
  }));

  // Subscribe to subsequent changes.
  final sub = connectivity.onConnectivityChanged.listen((results) {
    if (controller.isClosed) return;
    controller.add(isOnline(results));
  }, onError: (Object e) {
    if (kDebugMode) debugPrint('[Connectivity] stream error: $e');
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Convenience: a synchronous boolean for callers that only care about the
/// last-known state (e.g. retry buttons that want to gate their tap on online).
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).maybeWhen(
        data: (online) => online,
        // While loading or on error, assume online so we don't block UX.
        orElse: () => true,
      );
});
