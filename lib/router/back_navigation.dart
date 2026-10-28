// =============================================================================
// AZAMAN — THE ONE BACK CONTRACT  (PR-B)
//
// The app's back experience must behave like normal phone navigation: back
// returns to the actual preceding surface. This app keeps routes on ONE
// root navigator with three KINDS of things on top of it:
//
//   1. TRANSIENT SURFACES — dialogs, modal bottom sheets, drawers,
//      imperative sibling screens. These are plain RouteSettings-backed
//      routes (GoRouter renders only its own pages as Page-backed ones —
//      see router/top_route_observer.dart for the discriminator).
//   2. ROUTER PAGES — GoRouter-owned, Page-backed, deep-linkable.
//   3. THE ROOT — the router's base page ('/' → splash/boot), below the
//      imperative shell (MainWrapper) the user actually lives in.
//
// The precedence is ONE list, applied identically by every back affordance:
//
//   1. An imperative surface (screen / sheet / dialog) covers the top
//      router page → the ROOT navigator owns the pop (`maybePop`, so
//      pop-disposition-aware routes and dialogs behave), exactly ONE
//      level per action.
//   2. The top is a router page → pop it THROUGH THE ROUTER (the router
//      is the single owner of its stack; popping its pages behind the
//      router's back would desync location and state).
//   3. Nothing to return to → the honest root fallback: the canonical
//      home route, never a fabricated "previous page".
//
// The PLATFORM back action follows the same precedence natively: Android
// system/predictive back resolves through the root navigator's maybePop
// (which pops transient routes, then hands the router's pages to GoRouter
// through its page-delegate) and never touches a custom detector. The
// visible contextual back chevron (widgets/contextual_nav_band.dart) calls
// [AzBackNavigation.handleBack] so both paths share this one contract.
//
// A back action is consumed EXACTLY ONCE: one call pops one level and
// re-evaluates from the new top on the next call. The top-route kind
// observer updates synchronously inside the navigator's didPop, so a
// second rapid press cannot double-apply a single gesture.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:azaman/router/route_depth.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/router/top_route_observer.dart';

/// The app's single back contract. See the file header for the precedence.
abstract final class AzBackNavigation {
  /// Handles ONE back action from [context].
  ///
  /// [context] must sit under the root navigator (any widget inside the
  /// app's widget tree qualifies; the contextual nav band supplies it).
  static void handleBack(BuildContext context) {
    // 1. An imperative surface owns the screen: the root navigator pops
    //    exactly that topmost route. maybePop (not pop) so dialogs and
    //    pop-disposition-aware routes behave.
    if (!topRouteObserver.topRouteIsRouterPage) {
      Navigator.of(context, rootNavigator: true).maybePop();
      return;
    }
    final router = RouteDepthTrackerHost.of(context).router;
    // 2. A router page is topmost: the router pops its own page.
    if (router.canPop()) {
      router.pop();
      return;
    }
    // 3. Honest root fallback (deep link with nothing under it): the
    //    canonical root — never a fabricated previous route.
    router.go(AzRoutes.home);
  }
}
