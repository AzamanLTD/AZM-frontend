// =============================================================================
// NAV BAND CLEARANCE  (Persistent-nav occlusion fix, 2026-10-13)
//
// THE PROBLEM THIS FILE EXISTS FOR
// --------------------------------
// The shell runs `Scaffold(extendBody: true, bottomNavigationBar:
// PremiumBottomNav)`. Tab content therefore paints BEHIND the persistent
// band — and until now each page guessed its own bottom padding with magic
// numbers (120, 120, 106…). A guess that is too small on one device hides
// the last interactive item behind the band; a guess that is too large
// wastes a strip of screen on every other device.
//
// THE SINGLE SOURCE OF TRUTH
// -------------------------
// Flutter's Scaffold (extendBody: true) ALREADY publishes the live
// bottom-widget height into the body's MediaQuery:
//
//     padding.bottom = max(system safe-area bottom, band height)
//
// That value tracks the band itself — compression while scrolling, the
// IME-riding pad while the band's search field has focus, and the device's
// safe area — with zero hardcoded numbers. Every tab page keeps
// `SafeArea(bottom: false)` so the inset survives to this call.
//
//     final clearance = navBandClearance(context);   // exact, live
//
// On routes WITHOUT the persistent band (pushed screens live above the
// shell), the same call degrades to the system safe-area bottom — so a
// widget can use it uniformly and never over-pad a band-less surface.
//
// [AzSpace.navClearanceHeight] remains ONLY where a constraint-STABLE
// number is genuinely required (Home's fold composition measures against
// a fixed extent; it must not re-read mid-gesture). Everything else reads
// the live value.
// =============================================================================

import 'package:flutter/widgets.dart';

/// The live bottom clearance of the persistent nav band, in logical pixels.
///
/// Under the shell this is the exact height the band eats from the page
/// (including the safe area); away from the shell it is just the safe area.
double navBandClearance(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Breathing room kept between the last interactive item and the band.
///
/// "Reachable" should not mean "kissing the pill's top edge": content that
/// ends exactly at the band is visually cramped and half a finger-width of
/// overshoot feels like a miss. Every clearance-consuming surface adds this
/// gap on top of [navBandClearance].
const double kNavBandGap = 16;
