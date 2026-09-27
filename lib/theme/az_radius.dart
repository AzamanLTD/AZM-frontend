// =============================================================================
// AZAMAN â€” RADIUS SCALE
//
// The single corner-radius ladder for the entire app.
//
// WHY THIS EXISTS
// The codebase had 1,410 `BorderRadius.circular(...)` calls across 29 distinct
// values (2,3,4,5,6,6.5,7,8,9,10,11,12,13,14,15,16,18,20,22,24,26,28,30,31,
// 99,100,999). That is not a design system, it is entropy â€” two cards sitting
// next to each other rounded at 12 and 14 read as a mistake to the eye even
// when the user cannot name why.
//
// The ladder below is anchored on the values the app already uses MOST, so
// migration is almost always a Â±2px nudge rather than a redesign:
//
//   step   absorbs                    dominant original
//   xs     2, 3, 4, 5                 4   (72 uses)
//   sm     6, 7, 8, 9                 8   (110 uses)
//   md     10, 11, 12, 13             12  (392 uses)  â† most used in the app
//   lg     14, 15, 16, 17             14  (185 uses)
//   xl     18, 19, 20, 22             20  (128 uses)
//   xxl    24, 26, 28, 30, 31         28
//   pill   99, 100, 999               full round
//
// MIGRATION POLICY (important)
// Do NOT bulk-replace existing radii. Migrate one screen at a time as part of
// that screen's own task, so every radius change is visually reviewed in
// context. TASK-001 only creates the scale.
//
// USAGE
//   BorderRadius.circular(AzRadius.md)        // imperative
//   AzRadius.brMd                             // const, preferred in const trees
//   AzRadius.sheetTop                         // bottom-sheet top corners
// =============================================================================

import 'dart:ui' show Radius;
import 'package:flutter/widgets.dart' show BorderRadius;

/// Corner-radius ladder. See file header for the migration policy.
abstract final class AzRadius {
  // â”€â”€ RAW VALUES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// 4 â€” micro chips, tiny badges, hairline pills, inner thumbnails.
  static const double xs = 4;

  /// 8 â€” small controls: tags, tiny buttons, inline inputs.
  static const double sm = 8;

  /// 12 â€” the workhorse. Buttons, inputs, list rows, small cards.
  static const double md = 12;

  /// 16 â€” standard cards, tiles, image containers.
  static const double lg = 16;

  /// 20 â€” large cards, hero panels, section containers.
  static const double xl = 20;

  /// 28 â€” bottom sheets, full-bleed panels, stage surfaces.
  static const double xxl = 28;

  /// 999 â€” fully rounded: nav pill, avatar rings, status pills.
  static const double pill = 999;

  // â”€â”€ CONST BorderRadius PRESETS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Use these inside `const` widget trees. `BorderRadius.circular(x)` is NOT
  // a const constructor; `BorderRadius.all(Radius.circular(x))` IS.
  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));

  // â”€â”€ DIRECTIONAL PRESETS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Bottom-sheet / stage top corners at the `xxl` step.
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(xxl));

  /// Bottom-sheet / stage top corners at the `xl` step.
  static const BorderRadius sheetTopLg =
      BorderRadius.vertical(top: Radius.circular(xl));

  /// Top-only rounding for headers sitting on a scrolled list.
  static const BorderRadius topLg =
      BorderRadius.vertical(top: Radius.circular(lg));

  // â”€â”€ HELPERS (non-const contexts) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Rounded on all corners by [r]. Prefer the const presets above.
  static BorderRadius all(double r) => BorderRadius.circular(r);

  /// Rounded on the top two corners by [r].
  static BorderRadius top(double r) =>
      BorderRadius.vertical(top: Radius.circular(r));

  /// Rounded on the bottom two corners by [r].
  static BorderRadius bottom(double r) =>
      BorderRadius.vertical(bottom: Radius.circular(r));

  /// Rounded on the outer two corners only, with a smaller radius on the inner
  /// corners â€” the shape a card takes at the END of a fanned deck.
  ///
  /// A "squircle-adjacent" shape: sharp on the outer corner, rounded inward.
  /// Used for stacked / fanned card decks (marketplace shelf, tray fan).
  static BorderRadius fanned(double r, {required bool left}) => BorderRadius.only(
        topLeft: Radius.circular(left ? r : r * 0.35),
        bottomLeft: Radius.circular(left ? r : r * 0.35),
        topRight: Radius.circular(left ? r * 0.35 : r),
        bottomRight: Radius.circular(left ? r * 0.35 : r),
      );
}
