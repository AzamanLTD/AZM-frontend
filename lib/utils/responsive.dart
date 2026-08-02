// =============================================================================
// AZAMAN — RESPONSIVE LAYOUT UTILITIES
//
// A single, standalone breakpoint vocabulary for adapting layouts from phone
// to tablet to desktop/web. Standalone and additive: nothing in the codebase
// depends on this yet — screens opt in by reading `Responsive.*` or wrapping
// their body in an `AdaptiveLayout`. No existing widget is changed by adding
// this file.
//
// Breakpoints follow Material's window-size classes (compact / medium /
// expanded), measured against the shortest-usable width:
//
//   < 600   → mobile   (phones, compact)
//   600–899 → tablet   (medium)
//   ≥ 1200  → desktop  (expanded; web + desktop targets)
//
// Usage:
//   if (Responsive.isMobile(context)) ...
//   final cols = Responsive.gridColumns(context);
//   Padding(padding: Responsive.pagePadding(context), child: ...)
//
//   AdaptiveLayout(
//     mobile:  MobileBody(),
//     tablet:  TabletBody(),   // optional — falls back to mobile
//     desktop: DesktopBody(),  // optional — falls back to tablet, then mobile
//   )
// =============================================================================

import 'package:flutter/widgets.dart';

/// Static helpers for querying the current window size class.
///
/// All getters read [MediaQuery] and are cheap, but because they depend on
/// `MediaQuery.of(context)` a widget that calls them will rebuild when the
/// window is resized — which is exactly what you want for responsive layout.
class Responsive {
  const Responsive._();

  /// Upper bound (exclusive) of the mobile / compact range.
  static const double mobileBreakpoint = 600;

  /// Upper bound (exclusive) of the tablet / medium range.
  static const double tabletBreakpoint = 900;

  /// Lower bound (inclusive) of the desktop / expanded range.
  static const double desktopBreakpoint = 1200;

  static double width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isMobile(BuildContext context) =>
      width(context) < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = width(context);
    return w >= mobileBreakpoint && w < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      width(context) >= desktopBreakpoint;

  /// Returns whichever of [mobile] / [tablet] / [desktop] matches the current
  /// width, falling back narrower→wider when an option is omitted
  /// (desktop → tablet → mobile). Handy for one-off values like font sizes or
  /// counts without branching:
  ///
  ///   final pad = Responsive.value(context, mobile: 16.0, desktop: 32.0);
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  /// Page-level padding that grows with available width.
  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.all(
        value(context, mobile: 16, tablet: 24, desktop: 32),
      );

  /// Sensible default column count for content grids.
  static int gridColumns(BuildContext context) =>
      value(context, mobile: 1, tablet: 2, desktop: 3);
}

/// Picks one of three subtrees based on the current window size class.
///
/// Only [mobile] is required; [tablet] and [desktop] fall back to the next
/// narrower body when null (desktop → tablet → mobile), so you can adopt wider
/// layouts incrementally.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (Responsive.isTablet(context)) return tablet ?? mobile;
    return mobile;
  }
}
