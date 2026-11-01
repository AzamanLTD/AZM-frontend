// =============================================================================
// AZAMAN — BALANCE CARD BRAND IDENTITY (SINGLE SOURCE OF TRUTH)
//
// One balance-card identity now drives TWO things:
//   1. the physical card face the Home wallet renders (card palette below);
//   2. the app's brand accent everywhere (BrandAccent below).
//
// The FOUR variants (azablue / azagreen / azadark / azared) are four
// COLOURWAYS of ONE design: identical geometry, logo block, chip, contour work
// and content placement. Only the palette differs. Nothing in this file knows about
// widgets; the painter reads [AzamanCardPalette], the theme reads
// [BrandAccent]. A future brand redesign changes these two records, not the
// wallet interaction or any money logic.
//
// Palette values were sampled from the supplied reference art:
//   azablue  gradient from bright #1A6BD4 (top-right) through #0A499E to
//            deep #003072 (bottom-left); silver chip #CFCDCC
//   azagreen olive gradient #747B5D -> #596145 -> #475139; warm chip #BBB1A7
//   azadark  graphite gradient #30343E -> #161D26 -> #111821; chip #B8AFAA
//   azared   (no reference supplied) built to the same construction as a
//            premium oxide red: #8E1B2C bright -> #6B1220 mid -> #4A0E17 deep
//
// Accent tones are deliberate ACCESSIBLE companions of each card, not raw
// copies of card pixels: a card face is a large flat surface, an accent is
// text and controls on the app's own surfaces, so the light accents are the
// deep 700-range tones (readable on white) and the dark accents are luminous
// tints (readable on the app's near-black). Raw card RGB values would fail
// contrast in one of the two themes.
// =============================================================================

import 'package:flutter/widgets.dart';

/// Which balance-card face is applied. This is the app's brand identity.
///
/// Deliberately separate from:
///   • the Visa card surface,
///   • the peer-transfer chat card,
///   • the backend `equippedCardSkin` field (a documented different concept).
enum BalanceCardVariant {
  blue,
  green,
  dark,
  red;

  /// Persisted value. Stable strings, never indices, so enum order can never
  /// silently remap a user's saved card.
  String get storageValue => switch (this) {
    BalanceCardVariant.blue => 'azablue',
    BalanceCardVariant.green => 'azagreen',
    BalanceCardVariant.dark => 'azadark',
    BalanceCardVariant.red => 'azared',
  };

  /// Human label for the selector and settings.
  String get label => switch (this) {
    BalanceCardVariant.blue => 'Blue',
    BalanceCardVariant.green => 'Green',
    BalanceCardVariant.dark => 'Dark',
    BalanceCardVariant.red => 'Red',
  };
}

/// The SharedPreferences key for the applied card variant. A dedicated key,
/// never a reuse of the legacy independent-accent preference.
const String kBalanceCardVariantPrefKey = 'azaman_balance_card_variant';

/// The LEGACY independent accent key. Read once during migration only, then
/// scrubbed, so an old gold/teal/indigo/rose choice can never override the
/// card-driven identity.
const String kLegacyAccentPrefKey = 'azaman_accent';

/// Parses a persisted value, tolerating legacy/corrupt entries. The fresh
/// install default is BLUE.
BalanceCardVariant balanceCardVariantFromStorage(Object? raw) {
  final s = raw?.toString();
  for (final v in BalanceCardVariant.values) {
    if (v.storageValue == s || v.name == s) return v;
  }
  return BalanceCardVariant.blue;
}

/// The brand accent set the theme consumes for one brightness.
class BrandAccent {
  final Color accent;
  final Color onAccent;
  final Color secondary;

  const BrandAccent({
    required this.accent,
    required this.onAccent,
    required this.secondary,
  });
}

/// The card face's own colours (what the painter draws).
class AzamanCardPalette {
  /// Gradient stops, bright -> mid -> deep, laid top-right to bottom-left
  /// exactly like the references.
  final Color bright;
  final Color mid;
  final Color deep;

  /// Contour ("groove") strokes: a light line and its dark partner, both very
  /// low alpha, which together read as an embossed curve rather than a wire.
  final Color contourLight;
  final Color contourDark;

  /// The metallic chip.
  final Color chipHigh;
  final Color chipBase;
  final Color chipLow;
  final Color chipLine;

  /// Ink ON the card (both faces).
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color inkDivider;
  final Color inkAccent;

  const AzamanCardPalette({
    required this.bright,
    required this.mid,
    required this.deep,
    required this.contourLight,
    required this.contourDark,
    required this.chipHigh,
    required this.chipBase,
    required this.chipLow,
    required this.chipLine,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkDivider,
    required this.inkAccent,
  });
}

const Map<BalanceCardVariant, AzamanCardPalette> kCardPalettes = {
  BalanceCardVariant.blue: AzamanCardPalette(
    bright: Color(0xFF1A6BD4),
    mid: Color(0xFF0A499E),
    deep: Color(0xFF003072),
    contourLight: Color(0x14FFFFFF),
    contourDark: Color(0x1A001A3D),
    chipHigh: Color(0xFFE9E7E4),
    chipBase: Color(0xFFCFCDCC),
    chipLow: Color(0xFFA7A29C),
    chipLine: Color(0xFF8A857F),
    inkPrimary: Color(0xFFF7FAFF),
    inkSecondary: Color(0xB8EAF1FF),
    inkTertiary: Color(0x85D3E2F8),
    inkDivider: Color(0x33DCE9FF),
    inkAccent: Color(0xFFBFD9FF),
  ),
  BalanceCardVariant.green: AzamanCardPalette(
    bright: Color(0xFF747B5D),
    mid: Color(0xFF596145),
    deep: Color(0xFF475139),
    contourLight: Color(0x14F3F0DF),
    contourDark: Color(0x220E1408),
    chipHigh: Color(0xFFDCD6CE),
    chipBase: Color(0xFFBBB1A7),
    chipLow: Color(0xFF948C82),
    chipLine: Color(0xFF7D766C),
    inkPrimary: Color(0xFFF4F2E4),
    inkSecondary: Color(0xB8EDEADA),
    inkTertiary: Color(0x85D8D4C0),
    inkDivider: Color(0x33E8E4D2),
    inkAccent: Color(0xFFE8E8D8),
  ),
  BalanceCardVariant.dark: AzamanCardPalette(
    bright: Color(0xFF30343E),
    mid: Color(0xFF161D26),
    deep: Color(0xFF111821),
    contourLight: Color(0x12FFFFFF),
    contourDark: Color(0x33000000),
    chipHigh: Color(0xFFD9D3CD),
    chipBase: Color(0xFFB8AFAA),
    chipLow: Color(0xFF8F8881),
    chipLine: Color(0xFF6F6963),
    inkPrimary: Color(0xFFF2F4F8),
    inkSecondary: Color(0xB4E2E6EE),
    inkTertiary: Color(0x80C4CAD6),
    inkDivider: Color(0x2EE4E9F2),
    inkAccent: Color(0xFFC9D2E0),
  ),
  BalanceCardVariant.red: AzamanCardPalette(
    bright: Color(0xFF8E1B2C),
    mid: Color(0xFF6B1220),
    deep: Color(0xFF4A0E17),
    contourLight: Color(0x14FFE3E6),
    contourDark: Color(0x220B0104),
    chipHigh: Color(0xFFE7E1D9),
    chipBase: Color(0xFFC9C0B5),
    chipLow: Color(0xFFA0968B),
    chipLine: Color(0xFF83786D),
    inkPrimary: Color(0xFFFFF5F6),
    inkSecondary: Color(0xB8FFE6E9),
    inkTertiary: Color(0x85F5CDD3),
    inkDivider: Color(0x33FFE1E6),
    inkAccent: Color(0xFFFFC9D2),
  ),
};

/// The accent family the app theme uses for an applied card, per brightness.
/// Contrast was checked against the app's real surfaces: the light accents
/// clear 7:1 on white, the dark accents clear 6:1 on the near-black.
BrandAccent brandAccentFor(BalanceCardVariant variant, bool isDark) {
  switch (variant) {
    case BalanceCardVariant.blue:
      return isDark
          ? const BrandAccent(
              accent: Color(0xFF4F9BF0),
              onAccent: Color(0xFF06101E),
              secondary: Color(0xFF8CC0F8),
            )
          : const BrandAccent(
              accent: Color(0xFF0B4A9E),
              onAccent: Color(0xFFF7FAFF),
              secondary: Color(0xFF1567C8),
            );
    case BalanceCardVariant.green:
      return isDark
          ? const BrandAccent(
              accent: Color(0xFFA8B283),
              onAccent: Color(0xFF10160A),
              secondary: Color(0xFFC7CFA6),
            )
          : const BrandAccent(
              accent: Color(0xFF4F5A33),
              onAccent: Color(0xFFF6F7EC),
              secondary: Color(0xFF6B7752),
            );
    case BalanceCardVariant.dark:
      return isDark
          ? const BrandAccent(
              accent: Color(0xFFB9C0CC),
              onAccent: Color(0xFF0C1016),
              secondary: Color(0xFFD6DBE3),
            )
          : const BrandAccent(
              accent: Color(0xFF2C3441),
              onAccent: Color(0xFFF5F7FA),
              secondary: Color(0xFF4E5766),
            );
    case BalanceCardVariant.red:
      return isDark
          ? const BrandAccent(
              accent: Color(0xFFF0788C),
              onAccent: Color(0xFF1A0509),
              secondary: Color(0xFFFFA6B4),
            )
          : const BrandAccent(
              accent: Color(0xFF9E1B2E),
              onAccent: Color(0xFFFFF5F6),
              secondary: Color(0xFFC22B41),
            );
  }
}

// =============================================================================
// MARKETPLACE CATEGORY IDENTITY  (fixed, semantic, palette-derived)
//
// The Marketplace KEEPS its per-category colour identity: Shop, Stay, Eat and
// Ride must stay visually distinguishable at a glance. What it must not keep
// is a SECOND, disconnected collection of arbitrary colours. Each vertical now
// takes its hue from the SAME four card palettes, through a FIXED mapping:
//
//     Shop -> azadark (graphite)   Stay -> azablue
//     Eat  -> azagreen             Ride -> azared
//
// The mapping is semantic, not personal: Stay stays blue even when the user's
// own balance card is green. Category colour therefore never reads the applied
// variant and can never mutate it — a vertical only BORROWS its accent for the
// duration of its route (see AzVerticalAccentScope).
//
// The accents are contrast-resolved companions of the card palettes rather
// than raw card pixels: a card face is a large flat surface, a chip or a pill
// is small type on the app's own surface, so each vertical resolves to the
// tone that actually reads in the current brightness.
// =============================================================================

/// The four Marketplace verticals that own a colour identity.
enum MarketplaceVertical { shop, stay, eat, ride }

/// The FIXED vertical -> card-palette mapping. Do not make this depend on the
/// applied card: category identity must be stable across users.
const Map<MarketplaceVertical, BalanceCardVariant> kVerticalCardVariant = {
  MarketplaceVertical.shop: BalanceCardVariant.dark,
  MarketplaceVertical.stay: BalanceCardVariant.blue,
  MarketplaceVertical.eat: BalanceCardVariant.green,
  MarketplaceVertical.ride: BalanceCardVariant.red,
};

/// The brand accent a Marketplace vertical borrows, resolved for brightness
/// from that vertical's card palette. This is the ONLY way a category should
/// reach for its colour.
BrandAccent verticalAccentFor(MarketplaceVertical vertical, bool isDark) {
  final variant = kVerticalCardVariant[vertical] ?? BalanceCardVariant.dark;
  return brandAccentFor(variant, isDark);
}
