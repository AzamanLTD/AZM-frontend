// =============================================================================
// AZAMAN â€” SPACING SCALE  (4pt grid)
//
// WHY THIS EXISTS
// Screen padding and inter-element gaps were hand-picked per screen: the Home
// screen alone uses a hardcoded vertical rhythm of 8/16/16/18/28/28/28/28.
// Because nothing shared a step, the eye could not group anything â€” every
// block had the same weight and the same 16px inset, so the page read as a
// wall of equal bricks instead of a composition with a focal point.
//
// RULES
//   1. Every gap is a multiple of 4. If you need 13, you need 12 or 16.
//   2. Vary the rhythm. `xl` above a section header and `sm` between its rows
//      is what creates grouping. Uniform spacing creates none.
//   3. Use `AzSpace.pageH` for screen edge padding so every screen aligns to
//      the same optical gutter (currently 16).
//
// USAGE
//   const SizedBox(height: AzSpace.lg)
//   padding: const EdgeInsets.all(AzSpace.md)
//   padding: AzSpace.page
// =============================================================================

import 'package:flutter/widgets.dart' show EdgeInsets;

/// 4pt spacing ladder + EdgeInsets presets.
abstract final class AzSpace {
  // â”€â”€ RAW VALUES (4pt grid) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// 2 â€” optical nudges only (badge offset, icon baseline correction).
  static const double xxs = 2;

  /// 4 â€” hairline gaps inside a single control (icon â†” label).
  static const double xs = 4;

  /// 8 â€” tight gap between related elements (title â†” subtitle).
  static const double sm = 8;

  /// 12 â€” default gap between sibling rows.
  static const double md = 12;

  /// 16 â€” screen gutter, card inset, default block gap.
  static const double lg = 16;

  /// 20 â€” gap before a new group.
  static const double xl = 20;

  /// 24 â€” gap between sections.
  static const double xxl = 24;

  /// 32 â€” gap around a hero element.
  static const double xxxl = 32;

  /// 40 â€” breathing room around a full-bleed moment.
  static const double huge = 40;

  /// 48 â€” top-of-page lead-in, empty-state padding.
  static const double giant = 48;

  // â”€â”€ EdgeInsets PRESETS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Screen horizontal gutter only â€” for a screen's root column padding.
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);

  /// Screen gutter horizontally, `md` vertically.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg, vertical: md);

  /// Screen gutter horizontally, `xxl` at the top (for a scrolling page that
  /// sits under a floating header).
  static const EdgeInsets pageTop =
      EdgeInsets.only(left: lg, right: lg, top: xxl);

  /// Standard card interior.
  static const EdgeInsets cardInset = EdgeInsets.all(lg);

  /// Compact card interior (list rows, dense tiles).
  static const EdgeInsets cardInsetCompact =
      EdgeInsets.symmetric(horizontal: lg, vertical: md);

  /// Pill / chip interior.
  static const EdgeInsets chip =
      EdgeInsets.symmetric(horizontal: md, vertical: sm);

  /// Small pill / tag interior.
  static const EdgeInsets tag =
      EdgeInsets.symmetric(horizontal: sm, vertical: xs);

  /// Bottom padding that clears the floating nav pill.
  ///
  /// Derivation: pill height (62) + its bottom gutter (16) + ~42px of breathing
  /// room so the last card in a list is not visually crowded by the pill.
  ///
  /// **120 is not arbitrary â€” it is the value Home already uses**
  /// (`home_screen.dart` L81: `EdgeInsets.only(bottom: 120)`). It is promoted to
  /// a token so that if the pill's height ever changes, exactly one number
  /// changes. Do NOT lower this to a "tidier" number: content would slide under
  /// the pill and the bug would be invisible in review until a user hit it.
  static const double navClearanceHeight = 120;

  /// Ready-to-use inset form of [navClearanceHeight].
  static const EdgeInsets navClearance =
      EdgeInsets.only(bottom: navClearanceHeight);

  // â”€â”€ HELPERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Uniform inset by [v].
  static EdgeInsets all(double v) => EdgeInsets.all(v);

  /// Horizontal [h], vertical [v].
  static EdgeInsets xy(double h, double v) => EdgeInsets.symmetric(horizontal: h, vertical: v);
}
