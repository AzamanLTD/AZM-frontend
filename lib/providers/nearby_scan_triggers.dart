// lib/providers/nearby_scan_triggers.dart
// =============================================================================
// AZAMAN — NEARBY FOREGROUND SCAN TRIGGERS (Part 6.6 §E)
//
// Four allowed triggers, all foreground, all gated, all non-blocking:
//
//   1. Home mount — after the first frame, so first paint is never delayed.
//   2. App resume — debounced, because resume is noisy (sheet dismissals,
//      notification pulls and rotation can all fire it).
//   3. Home pull-to-refresh — the customer's own explicit gesture.
//   4. Entering Marketplace — the customer is browsing shops anyway.
//
// Every path funnels through ONE entry point, so the throttle, the feature
// gate, the preference and the app lock cannot be bypassed by using a
// different trigger. There is deliberately no timer, no background execution
// and no cold-start permission request.
// =============================================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/nearby_presence_controller.dart';

/// Debounce for the app-resume trigger. Long enough to collapse the burst of
/// activity that follows a resume, short enough to feel immediate.
const Duration nearbyResumeDebounce = Duration(seconds: 2);

/// Coalesces resume events and forwards everything to the controller, which
/// remains the single owner of gating, throttling and staleness.
class NearbyScanTriggers {
  NearbyScanTriggers({
    WidgetRef? ref,
    NearbyPresenceController? controller,
    this.resumeDebounce = nearbyResumeDebounce,
    DateTime Function()? clock,
  }) : assert(
         ref != null || controller != null,
         'NearbyScanTriggers needs a WidgetRef or an explicit controller',
       ),
       _ref = ref,
       _controllerOverride = controller,
       _clock = clock ?? DateTime.now;

  final WidgetRef? _ref;
  final NearbyPresenceController? _controllerOverride;
  final Duration resumeDebounce;
  final DateTime Function() _clock;

  Timer? _resumeTimer;
  DateTime? _lastResumeAt;

  NearbyPresenceController get _controller =>
      _controllerOverride ??
      _ref!.read(nearbyPresenceControllerProvider.notifier);

  /// Home mount. Deferred to after the first frame so the card paints first.
  void onHomeMounted() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.requestScan();
    });
  }

  /// App resume, debounced. Returns true when a scan was actually dispatched.
  bool onResumed() {
    final now = _clock();
    final last = _lastResumeAt;
    if (last != null && now.difference(last) < resumeDebounce) {
      return false; // still inside the debounce window
    }
    _lastResumeAt = now;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(resumeDebounce, () {
      _controller.requestScan();
    });
    return true;
  }

  /// The customer's own pull-to-refresh gesture. Explicit, so a "nothing
  /// found" result may say so.
  Future<void> onPullToRefresh() => _controller.requestScan(explicit: true);

  /// Entering the marketplace. Not explicit: the customer did not ask for a
  /// proximity check, they asked to browse.
  void onMarketplaceEntered() {
    unawaited(_controller.requestScan());
  }

  void dispose() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }
}

/// Drop-in host that wires mount + lifecycle triggers for one subtree and
/// disposes the timers. Additive: it wraps, it does not alter the child.
class NearbyScanTriggerHost extends ConsumerStatefulWidget {
  const NearbyScanTriggerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NearbyScanTriggerHost> createState() =>
      _NearbyScanTriggerHostState();
}

class _NearbyScanTriggerHostState extends ConsumerState<NearbyScanTriggerHost>
    with WidgetsBindingObserver {
  NearbyScanTriggers? _triggers;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _triggers = NearbyScanTriggers(ref: ref)..onHomeMounted();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggers?.onResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _triggers?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
