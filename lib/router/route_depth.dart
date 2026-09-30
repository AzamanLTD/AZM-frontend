// =============================================================================
// AZAMAN — ROUTE-STACK DEPTH SIGNAL  (NEW-A, Step 6)
//
// The hand-off contract to NEW-C (depth-aware contextual navigation).
//
// NEW-C must NEVER infer depth from screen names or widget scaffolding.
// This file owns the single, router-derived answer:
//
//     RouteDepthTracker.of(context)   →  tracker
//     tracker.depth                   →  0 at root/home, +1 per
//                                        hierarchical step
//     tracker.routeNames             →  breadcrumb of GoRouter names
//
// Depth definition (deliberately two-sided — see effectiveDepth):
//
//   * NATURAL navigation: the user pushed [home, detail] — the router
//     stack length carries the depth (stack.length - 1).
//   * DEEP-LINKED detail: the router stack may contain ONLY the detail
//     route ([/susu/123]), but the user's effective position in the
//     hierarchy is unchanged — /susu/123 IS one level below home. So
//     effective depth also derives from the path's segment count:
//     '/' → 0, '/transactions' → 1, '/susu/123' → 1,
//     '/susu/123/contract' → 2.
//
//     effectiveDepth = max(stack.length - 1, pathSegmentCount)
//
// Both sides agree on every natural path (pushing deeper adds a stack
// entry and a segment together); the segment count alone rescues deep
// links, where the stack is short but the hierarchy position is real.
// Back navigation restores the previous depth, and parameter VALUES
// never matter — only segment structure. No widget special-cases
// anything; the router owns the answer.
// =============================================================================

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Depth of a location by path structure alone.
///
/// `'/'` is depth 0 — root/home. Every non-empty path segment adds one:
/// `'/susu/123/contract'` is depth 2 regardless of how it was reached.
int routeSegmentDepth(String location) {
  final path = location.split('?').first;
  return path.split('/').where((segment) => segment.isNotEmpty).length;
}

/// The effective depth of the current router state — see the header
/// contract. Never negative.
int effectiveDepth(GoRouter router) {
  final location = router.routeInformationProvider.value.uri.toString();
  final matches = router.routerDelegate.currentConfiguration.matches;
  final stackDepth = matches.isEmpty ? 0 : matches.length - 1;
  final segmentDepth = routeSegmentDepth(location);
  return stackDepth > segmentDepth ? stackDepth : segmentDepth;
}

/// Router-owned depth tracker. Constructed once with the app's GoRouter
/// (see app_router.dart) and listened to by whatever UI layer needs the
/// signal — NEW-C's contextual nav chrome mounts on it.
class RouteDepthTracker with ChangeNotifier {
  RouteDepthTracker(this._router) {
    _router.routerDelegate.addListener(_refresh);
    _refresh();
  }

  final GoRouter _router;

  int _depth = 0;
  List<String> _routeNames = const [];

  /// 0 at root/home; +1 per hierarchical step.
  int get depth => _depth;

  /// GoRouter names of the current match list, outermost first — the
  /// breadcrumb NEW-C renders. Empty when the location resolves no named
  /// route.
  List<String> get routeNames => List.unmodifiable(_routeNames);

  void _refresh() {
    final matches = _router.routerDelegate.currentConfiguration.matches;
    final names = matches
        .whereType<RouteMatch>()
        .map((m) => m.route.name)
        .whereType<String>()
        .toList(growable: false);
    final depth = effectiveDepth(_router);
    if (depth != _depth || !_listEquals(names, _routeNames)) {
      _depth = depth;
      _routeNames = names;
      notifyListeners();
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_refresh);
    super.dispose();
  }
}

/// Inherited access for widgets: `RouteDepthTracker.of(context).depth`.
///
/// The tracker is an app-scoped object owned by the router (see
/// app_router.dart); main.dart hosts it once at the root.
class RouteDepthTrackerHost extends InheritedWidget {
  const RouteDepthTrackerHost({
    super.key,
    required this.tracker,
    required super.child,
  });

  final RouteDepthTracker tracker;

  static RouteDepthTracker of(BuildContext context) {
    final host =
        context.dependOnInheritedWidgetOfExactType<RouteDepthTrackerHost>();
    assert(host != null,
        'No RouteDepthTrackerHost above this widget — main.dart hosts one.');
    return host!.tracker;
  }

  @override
  bool updateShouldNotify(RouteDepthTrackerHost oldWidget) =>
      oldWidget.tracker != tracker;
}
