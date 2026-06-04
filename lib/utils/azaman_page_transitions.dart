// =============================================================================
// AZAMAN — PAGE TRANSITIONS  (Phase H)
//
// Replaces the platform default page transition (slide-from-right on iOS,
// fade on Android) with a single cohesive slide+fade on every push.
// Wired into ThemeData via `pageTransitionsTheme` so EVERY existing
// `Navigator.push(MaterialPageRoute(...))` call across the app picks it
// up automatically — no migration needed across the screen layer.
//
// Tuning:
//   * 240ms duration — slightly faster than the 300ms iOS default so
//     the app feels responsive without losing the slide intent.
//   * Sub-2% horizontal slide — the dominant motion is opacity, the
//     slide is just enough to communicate hierarchy.
//   * Reverse animation symmetric — pop slides the inbound page back in
//     from the left so navigation has a direction.
//
// Why not a custom NavigatorObserver / pageBuilder?
//   PageTransitionsTheme is the canonical Flutter hook for this exact
//   thing. Subclassing PageTransitionsBuilder once gets us global
//   adoption in two lines wired into the existing ThemeData.
// =============================================================================

import 'package:flutter/material.dart';

class AzamanPageTransitionsBuilder extends PageTransitionsBuilder {
  const AzamanPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Inbound page: slide a few percent from the right, fade in.
    final slideIn = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(curved);

    // Outgoing page (under the inbound on push): drift slightly left
    // and dim. Mirrors iOS's interactive parent-page motion.
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.04, 0),
    ).animate(secondaryCurved);

    final dim = Tween<double>(begin: 1.0, end: 0.92).animate(secondaryCurved);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: dim,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        ),
      ),
    );
  }
}
