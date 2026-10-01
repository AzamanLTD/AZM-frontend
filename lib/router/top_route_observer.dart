// =============================================================================
// AZAMAN — TOP-ROUTE KIND OBSERVER  (NEW-C)
//
// The contextual nav band (see widgets/contextual_nav_band.dart) must be
// VISIBLE exactly when the topmost route on the root navigator is a
// router-owned page at depth ≥ 1 — and hidden whenever anything else owns
// the screen above it:
//
//   * a sanctioned imperative screen pushed above a router page (the
//     routing contract keeps sibling-to-sibling navigation imperative),
//   * a sheet, a dialog or a drawer route.
//
// The band lives in the MaterialApp builder, ABOVE the navigator, so it
// cannot rely on its own position to know what covers the page. This
// observer is the single honest answer: GoRouter renders every route it
// owns as a Page-backed route (its pageBuilder families wrap each screen
// in a MaterialPage / CustomTransitionPage), while every imperative push
// (MaterialPageRoute, showModalBottomSheet, showDialog, …) creates a
// route whose `settings` is a plain RouteSettings. So:
//
//     route.settings is Page   →  router-owned page
//     otherwise                →  imperative overlay route
//
// The observer records only the KIND of the current topmost route. It
// never touches navigation, never inspects contents, and notifies
// (coalesced to one microtask) so chrome can rebuild after the navigator
// has finished mutating — notifying synchronously from didPush/didPop
// would rebuild listeners DURING the navigator's build frame.
// =============================================================================

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Listens to the root navigator and exposes whether the CURRENT TOPMOST
/// route is router-owned (Page-backed) or an imperative overlay.
///
/// Registered once on the GoRouter (`observers: [topRouteObserver]`,
/// see router/app_router.dart) and listened to by the contextual nav band.
class TopRouteKindObserver extends NavigatorObserver with ChangeNotifier {
  TopRouteKindObserver();

  /// The kind of the topmost route the observer has seen so far. Starts
  /// `true` (the navigator's initial route is always a router page).
  bool _topIsPage = true;

  /// Whether the current topmost route is a router-owned page — i.e. no
  /// imperative route (screen / sheet / dialog) covers it.
  bool get topRouteIsRouterPage => _topIsPage;

  int _notifyScheduled = 0;

  void _update(bool topIsPage) {
    if (_topIsPage == topIsPage) return;
    _topIsPage = topIsPage;
    _scheduleNotify();
  }

  /// Coalesce notifications into ONE microtask: several pushes/pops can
  /// land inside a single navigator frame, and listeners (the band) must
  /// rebuild once, after the frame's mutations complete.
  void _scheduleNotify() {
    if (_notifyScheduled > 0) return;
    _notifyScheduled++;
    scheduleMicrotask(() {
      _notifyScheduled = 0;
      notifyListeners();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(route.settings is Page);
  }

  static bool _isPage(Route<dynamic>? route) =>
      route != null && route.settings is Page;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // `previousRoute` is the route BELOW the popped one — the new top.
    _update(_isPage(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _update(_isPage(newRoute));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _update(_isPage(previousRoute));
  }
}

/// The app-scoped observer instance. One navigator, one observer.
final TopRouteKindObserver topRouteObserver = TopRouteKindObserver();
