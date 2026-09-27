// =============================================================================
// AZAMAN â€” ELEVATION / LIGHTING LADDER
//
// WHY THIS EXISTS
// The app has 104 `BoxShadow` sites, almost all of them a single soft shadow
// centred under the element. A single centred shadow makes a surface read as
// "a rectangle with a blur", not as an object sitting above a plane.
//
// Real depth comes from TWO shadows working together:
//   â€¢ a tight, dark contact shadow  â†’ tells the eye the object is CLOSE
//   â€¢ a wide, faint ambient shadow  â†’ tells the eye the object is RAISED
// Plus a single implied light source. Azaman's light comes from the TOP-LEFT,
// which means:
//   â€¢ top / left rim  = lighter  (the light catches the edge)
//   â€¢ bottom / right  = darker   (the edge falls away)
//   â€¢ shadow offsets DOWN and slightly RIGHT
//
// Every recipe below follows that rule. `PremiumGlassContainer` (TASK-005)
// uses the same rule for its rim, so the whole app agrees on where the light is.
//
// USAGE
//   decoration: BoxDecoration(
//     borderRadius: AzRadius.brXl,
//     boxShadow: AzElevation.level2(colors.isDark),
//   )
// =============================================================================

import 'package:flutter/widgets.dart' show BoxShadow, Color, Offset;

/// Opaque black. Declared locally rather than using `Colors.black`, because
/// `Colors` lives in `package:flutter/material.dart` and this token file
/// deliberately depends only on `flutter/widgets.dart` so it stays usable
/// from pure-widget contexts (and from `dart:ui`-only code).
const Color _kShadowBase = Color(0xFF000000);

/// Shadow recipes. Always pass the current `colors.isDark`.
///
/// Dark mode needs *stronger* shadows than light mode, because a black shadow
/// on a black background is nearly invisible â€” dark surfaces read as raised
/// mostly through rim light (see `PremiumGlassContainer`). The alpha values
/// below are tuned for that asymmetry.
abstract final class AzElevation {
  /// Level 0 â€” flush with the plane. No shadow. Lists, section backgrounds,
  /// anything that should not appear to float.
  static const List<BoxShadow> level0 = <BoxShadow>[];

  /// Level 1 â€” resting card. Barely lifted. Use for dense grids where a
  /// stronger shadow would create visual noise between neighbours.
  static List<BoxShadow> level1(bool isDark, {Color? color}) {
    final base = color ?? _kShadowBase;
    return <BoxShadow>[
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.30 : 0.05),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.18 : 0.03),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Level 2 â€” the default for a primary card. This is the recipe the app
  /// should use almost everywhere.
  static List<BoxShadow> level2(bool isDark, {Color? color}) {
    final base = color ?? _kShadowBase;
    return <BoxShadow>[
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.36 : 0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.26 : 0.05),
        blurRadius: 28,
        offset: const Offset(0, 10),
      ),
    ];
  }

  /// Level 3 â€” floating chrome: the nav pill, a HUD, a docked tray.
  static List<BoxShadow> level3(bool isDark, {Color? color}) {
    final base = color ?? _kShadowBase;
    return <BoxShadow>[
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.42 : 0.08),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.34 : 0.07),
        blurRadius: 34,
        offset: const Offset(0, 14),
      ),
    ];
  }

  /// Level 4 â€” a modal / sheet that has taken over the screen.
  static List<BoxShadow> level4(bool isDark, {Color? color}) {
    final base = color ?? _kShadowBase;
    return <BoxShadow>[
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.50 : 0.10),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: base.withValues(alpha: isDark ? 0.44 : 0.09),
        blurRadius: 48,
        offset: const Offset(0, 20),
      ),
    ];
  }

  /// A coloured "glow" shadow â€” for a single hero element per screen that
  /// should appear to emit light (holographic card, active CTA, live badge).
  ///
  /// [intensity] 0.0â€“1.0. Keep it â‰¤ 0.45; a glow that is too strong reads as
  /// a rendering bug rather than as light.
  static List<BoxShadow> glow(Color tint, {double intensity = 0.32, double blur = 32}) {
    return <BoxShadow>[
      BoxShadow(
        color: tint.withValues(alpha: intensity),
        blurRadius: blur,
        spreadRadius: -4,
        offset: Offset.zero,
      ),
    ];
  }

  // â”€â”€ RIM-LIGHT HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // The same top-left light source that drives the shadows above also drives
  // these edge colours. Use them anywhere you hand-build a border so the whole
  // app agrees on where the light is.

  /// Top / left edge â€” catches the light.
  static Color rimHighlight(bool isDark) =>
      isDark ? const Color(0x24FFFFFF) : const Color(0xB3FFFFFF);

  /// Bottom / right edge â€” falls away.
  static Color rimShade(bool isDark) =>
      isDark ? const Color(0x08FFFFFF) : const Color(0x0D000000);

  /// The inset hairline along the bottom edge that makes a surface read as
  /// *thick* rather than as a flat fill. Apply inside a clipped stack.
  static Color innerBottomShade(bool isDark) =>
      isDark ? const Color(0x1A000000) : const Color(0x0A000000);
}
