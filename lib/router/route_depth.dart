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
//   * NATURAL navigation: the user pushed [home, detail] — back returns
//     to the previous depth. The depth follows the CURRENT page's
//     matched route, so pushing and popping move the signal with the
//     stack exactly as the user perceives it.
//   * DEEP-LINKED detail: the router stack may contain ONLY the detail
//     route ([/susu/123]), but the user's effective position in the
//     hierarchy is unchanged — /susu/123 IS one level below home.
//     Because the answer derives from the matched ROUTE PATTERN (not
//     from the raw location, and not from the stack length), a deep
//     link and a natural push land on the identical depth.
//
// The router owns the answer:
//
//   * '/' → 0
//   * '/transactions' → 1
//   * '/susu/123' → 1   (pattern '/susu/:id' — the parameter VALUE is
//                        not a hierarchical step)
//   * '/susu/123/contract' → 2  (pattern '/susu/:id/contract')
//   * '/trade/abc' → 1  (pattern '/trade/:tradeId')
//   * '/dispute/abc' → 1
//
// Depth counts the LITERAL segments of the matched route's declared
// pattern. Parameter segments (':id') never contribute — only named
// structural steps do. The app's route table is a flat tree of
// full-pattern routes (see app_router.dart), so a match's declared
// pattern IS its full pattern; query strings never contribute either.
// =============================================================================

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Depth of a matched route by its declared pattern.
///
/// Counts the literal (non-parameter) path segments of [route]'s
/// pattern. `'/'` is depth 0; every named segment adds one. Parameter
/// placeholders (`':id'`, `'{id}'`) contribute nothing — a parameter
/// value is not a hierarchical step. Shell routes carry no path and
/// are transparent to the count.
int routePatternDepth(RouteBase route) {
  final pattern = route is GoRoute ? route.path : '';
  return pattern
      .split('/')
      .where((segment) =>
          segment.isNotEmpty &&
          !segment.startsWith(':') &&
          !segment.startsWith('{'))
      .length;
}

/// The effective depth of the current router state — see the header
/// contract. Never negative.
///
/// Derived from the deepest (current page's) match, so natural push,
/// back and deep links all resolve to the same structural depth.
int effectiveDepth(GoRouter router) {
  final matches = router.routerDelegate.currentConfiguration.matches;
  if (matches.isEmpty) return 0;
  // Matches are ordered outermost-first; the last match is the current
  // page. Shell routes contribute no literal segments, so they are
  // transparent to the count.
  return routePatternDepth(matches.last.route);
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
