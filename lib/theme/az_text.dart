// =============================================================================
// AZAMAN â€” TYPE SCALE
//
// WHY THIS EXISTS
// The app had 38 distinct `fontSize` values (6 â†’ 56) written inline, with
// 11 / 12 / 13 used 1,100 times between them. Three interchangeable sizes at
// the same visual weight means nothing can be *hierarchically* bigger â€” only
// numerically bigger. Weight was also being used as a hierarchy substitute
// (w700/w800/w900 everywhere), so nothing was actually emphasised.
//
// THE RULE
// In this scale, size + weight + tracking ALWAYS move together. You never pick
// "17px at w800" â€” you pick `AzText.title`, and 17/w600/âˆ’0.2 is what that means.
// If a design needs a different emphasis, it needs a different STEP, not a
// different weight on the same step.
//
// THE LADDER (10 steps + 3 specials)
//   hero      40  w800  âˆ’1.2   tabular-capable display figure (balance, big money)
//   display   32  w800  âˆ’1.0   screen hero title
//   titleXl   24  w700  âˆ’0.6   section hero, sheet hero
//   titleL    20  w700  âˆ’0.4   card headline
//   title     17  w600  âˆ’0.2   list-item title, sheet title
//   bodyL     15  w500   0.0   primary body copy
//   body      13.5 w500  0.0   secondary body copy
//   bodyS     12  w500  +0.1   metadata, captions with meaning
//   label     11  w600  +0.2   chips, nav labels, small buttons
//   caption   10  w600  +0.3   micro labels, badges, legal
//   â”€â”€ specials â”€â”€
//   button    14  w700  +0.1   every button label, app-wide
//   money(...)        w800  âˆ’1.0  tabular figures, for any currency amount
//   eyebrow   11  w700  +0.8   ALL-CAPS section eyebrow above a title
//
// MIGRATION POLICY (important)
// Do NOT bulk-replace existing TextStyles. Migrate one screen at a time as part
// of that screen's own task, so every typographic change is visually reviewed.
// TASK-002 only creates the scale; TASK-004 wires it into ThemeData.
//
// USAGE
//   Text('Balance', style: AzText.title.copyWith(color: colors.textPrimary))
//   Text(amount, style: AzText.money(colors.textPrimary, size: 40))
//   Text('RECENT', style: AzText.eyebrow.copyWith(color: colors.textTertiary))
// =============================================================================

// `FontFeature` is re-exported by `package:flutter/widgets.dart`, so this
// deliberately does NOT import `dart:ui` as well — a second source for the
// same symbol is an `unnecessary_import` and makes the dependency set lie.
import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/widgets.dart';

/// Locked type scale. See file header for the migration policy.
abstract final class AzText {
  // â”€â”€ RAW SIZES (for the rare case you must build a one-off style) â”€â”€â”€â”€â”€
  static const double sizeHero = 40;
  static const double sizeDisplay = 32;
  static const double sizeTitleXl = 24;
  static const double sizeTitleL = 20;
  static const double sizeTitle = 17;
  static const double sizeBodyL = 15;
  static const double sizeBody = 13.5;
  static const double sizeBodyS = 12;
  static const double sizeLabel = 11;
  static const double sizeCaption = 10;
  static const double sizeButton = 14;

  /// Tabular figures â€” every digit occupies the same width. **Mandatory for
  /// any number that can change**, otherwise a counting balance jitters
  /// horizontally as digits swap. This is the single most-missed detail in
  /// finance UI.
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ── FONT FAMILIES (UI-correction Phase A, 2026-10-03) ─────────────────────
  // The display/UI family is Comic Neue (the requested Comic-Sans-like feel
  // WITHOUT Comic Sans MS), bundled locally in pubspec.yaml — never fetched
  // at runtime, so a money app renders deterministically offline. The
  // numeric family stays Inter: money figures need tabular-figure stability
  // (every digit the same width) so a counting balance never jitters.
  static const String uiFamily = 'ComicNeue';
  static const String numericFamily = 'Inter';

  /// Comic Neue ships Regular (400) + Bold (700) only. Rather than leaving
  /// unavailable weights to the engine's closest-weight fallback, the theme
  /// maps them DELIBERATELY: 800/900 → 700, 600/500 → 400. W400 and W700
  /// ship as-is. Used by [uiTheme]; the Inter-based ladder ([theme]) is
  /// untouched so money surfaces keep their exact weights.
  static FontWeight mapUiWeight(FontWeight w) {
    switch (w) {
      case FontWeight.w800:
      case FontWeight.w900:
        return FontWeight.w700;
      case FontWeight.w500:
      case FontWeight.w600:
        return FontWeight.w400;
      default:
        return w; // w400, w700 (and lighter) exist in the family as-is
    }
  }

  // â”€â”€ THE LADDER â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Colors are intentionally null so these merge cleanly with whatever
  // DefaultTextStyle / colorScheme is in effect. Use `.copyWith(color: ...)`
  // when you need an explicit colour.

  /// 40 / w800 / âˆ’1.2 / h1.05 â€” hero display figure.
  static const TextStyle hero = TextStyle(
    fontSize: sizeHero,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1.05,
  );

  /// 32 / w800 / âˆ’1.0 / h1.10 â€” screen hero title.
  static const TextStyle display = TextStyle(
    fontSize: sizeDisplay,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    height: 1.10,
  );

  /// 24 / w700 / âˆ’0.6 / h1.20 â€” section hero, sheet hero.
  static const TextStyle titleXl = TextStyle(
    fontSize: sizeTitleXl,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.20,
  );

  /// 20 / w700 / âˆ’0.4 / h1.25 â€” card headline.
  static const TextStyle titleL = TextStyle(
    fontSize: sizeTitleL,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.25,
  );

  /// 17 / w600 / âˆ’0.2 / h1.30 â€” list-item title, sheet title.
  static const TextStyle title = TextStyle(
    fontSize: sizeTitle,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.30,
  );

  /// 15 / w500 / 0.0 / h1.40 â€” primary body copy.
  static const TextStyle bodyL = TextStyle(
    fontSize: sizeBodyL,
    fontWeight: FontWeight.w500,
    height: 1.40,
  );

  /// 13.5 / w500 / 0.0 / h1.45 â€” secondary body copy.
  static const TextStyle body = TextStyle(
    fontSize: sizeBody,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  /// 12 / w500 / +0.1 / h1.45 â€” metadata.
  static const TextStyle bodyS = TextStyle(
    fontSize: sizeBodyS,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.45,
  );

  /// 11 / w600 / +0.2 / h1.30 â€” chips, nav labels, small buttons.
  static const TextStyle label = TextStyle(
    fontSize: sizeLabel,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.30,
  );

  /// 10 / w600 / +0.3 / h1.30 â€” micro labels, badges, legal.
  static const TextStyle caption = TextStyle(
    fontSize: sizeCaption,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.30,
  );

  // â”€â”€ SPECIALS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// 14 / w700 / +0.1 â€” the label on every button, app-wide.
  static const TextStyle button = TextStyle(
    fontSize: sizeButton,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    height: 1.20,
  );

  /// 11 / w700 / +0.8 â€” an ALL-CAPS eyebrow sitting above a title.
  /// Always render the string in upper case at the call site.
  static const TextStyle eyebrow = TextStyle(
    fontSize: sizeLabel,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    height: 1.20,
  );

  // â”€â”€ MONEY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// A currency figure with tabular figures enabled. Use for **every** amount
  /// that can change on screen â€” balances, prices, rates, totals, countdowns.
  ///
  /// [size] defaults to 34 (a card balance). Use `AzText.sizeHero` (40) for a
  /// full-screen hero amount, `AzText.sizeTitle` (17) for an inline amount in
  /// a list row, `AzText.sizeBody` (13.5) for a delta chip.
  ///
  /// [weight] defaults to w800. Drop to w700 for a secondary amount so the
  /// primary figure still wins.
  static TextStyle money(
    Color color, {
    double size = 34,
    FontWeight weight = FontWeight.w800,
    double tracking = -1.0,
    double height = 1.0,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: tracking,
      height: height,
      color: color,
      // ALWAYS Inter — a font change here would introduce balance/amount
      // jitter the moment the UI family changes (UI-correction Phase A).
      fontFamily: numericFamily,
      fontFeatures: tabular,
    );
  }

  /// A small inline delta ("+GHâ‚µ 0.42") that pairs with a money figure.
  static TextStyle delta(Color color) => TextStyle(
        fontSize: sizeBody,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        height: 1.2,
        color: color,
        fontFamily: numericFamily,
        fontFeatures: tabular,
      );

  // â”€â”€ THEME WIRING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Maps the ladder onto Flutter's 15-slot `TextTheme` so that stock Material
  /// widgets (ListTile, AppBar titles, Chip labels, TextField) inherit Azaman
  /// typography instead of the M3 baseline.
  ///
  /// Returns a TextTheme with **null colours**. The caller is expected to run
  /// `.apply(bodyColor: ..., displayColor: ...)` â€” see TASK-004.
  static TextTheme theme() => const TextTheme(
        // Display
        displayLarge: hero,
        displayMedium: display,
        displaySmall: titleXl,
        // Headline
        headlineLarge: titleXl,
        headlineMedium: titleL,
        headlineSmall: title,
        // Title
        titleLarge: title,
        titleMedium: bodyL,
        titleSmall: body,
        // Body
        bodyLarge: bodyL,
        bodyMedium: body,
        bodySmall: bodyS,
        // Label
        labelLarge: button,
        labelMedium: label,
        labelSmall: caption,
      );

  /// The Comic-Neue UI text theme: the same 15-slot ladder as [theme], but
  /// every style carries [uiFamily] explicitly and runs through
  /// [mapUiWeight], so the theme never depends on ThemeData plumbing or
  /// engine weight fallback. Wire this (not [theme]) into ThemeData when the
  /// UI family is Comic Neue. Money surfaces never pass through here —
  /// [money] and [delta] carry [numericFamily] themselves.
  static TextTheme uiTheme() {
    TextStyle ui(TextStyle s) => s.copyWith(
          fontFamily: uiFamily,
          fontWeight: mapUiWeight(s.fontWeight ?? FontWeight.w400),
        );
    final t = theme();
    return TextTheme(
      displayLarge: ui(t.displayLarge!),
      displayMedium: ui(t.displayMedium!),
      displaySmall: ui(t.displaySmall!),
      headlineLarge: ui(t.headlineLarge!),
      headlineMedium: ui(t.headlineMedium!),
      headlineSmall: ui(t.headlineSmall!),
      titleLarge: ui(t.titleLarge!),
      titleMedium: ui(t.titleMedium!),
      titleSmall: ui(t.titleSmall!),
      bodyLarge: ui(t.bodyLarge!),
      bodyMedium: ui(t.bodyMedium!),
      bodySmall: ui(t.bodySmall!),
      labelLarge: ui(t.labelLarge!),
      labelMedium: ui(t.labelMedium!),
      labelSmall: ui(t.labelSmall!),
    );
  }
}
