// =============================================================================
// Storefront Theme Resolver
//
// Converts a ThemeTokenSet from the backend into Flutter ThemeData.
// Maps CSS-style hex tokens to Flutter ColorScheme / TextTheme.
// =============================================================================

import 'package:flutter/material.dart';
import '../models/storefront_models.dart';

class StorefrontThemeResolver {
  /// Build a complete Flutter ThemeData from a storefront theme.
  static ThemeData resolve(StorefrontThemeInfo theme) {
    final tokens = theme.tokenSet;
    final accent = _parseColor(tokens?.accent, const Color(0xFF6C4FD1));
    final accentHover = _parseColor(tokens?.accentHover, accent);

    final isDark = _isDarkColor(_parseColor(
      tokens?.background, const Color(0xFFF7F5F2)));
    final background = _parseColor(tokens?.background,
        isDark ? const Color(0xFF0F0E13) : const Color(0xFFF7F5F2));
    final surface = _parseColor(
        tokens?.surfaceSolid ?? tokens?.surface,
        isDark ? const Color(0xFF1E1C26) : Colors.white);
    final border = _parseColor(tokens?.border,
        isDark ? const Color(0x14FFFFFF) : const Color(0x14111111));
    final textPrimary = _parseColor(tokens?.textPrimary,
        isDark ? const Color(0xFFF0F0F5) : const Color(0xFF15141A));
    final textSecondary = _parseColor(tokens?.textSecondary,
        isDark ? const Color(0xFFC6BDCF) : const Color(0xFF5D5A66));
    final textMuted = _parseColor(tokens?.textMuted,
        isDark ? const Color(0xFF776589) : const Color(0xFF9A96A3));
    final danger = _parseColor(tokens?.danger, const Color(0xFFE15361));

    final radiusValue = _parseBorderRadius(theme.borderRadius);
    // SDUI is remote-controlled, so constrain the spacing multiplier before it
    // reaches widget padding. This prevents malformed business configuration
    // from producing negative/absurd layout constraints at runtime.
    final spacingScale = (theme.spacingScale ?? 1.0).clamp(0.5, 2.0).toDouble();

    final headingFont = theme.typography?['heading'] as String? ?? 'Inter';
    final bodyFont = theme.typography?['body'] as String? ?? 'Inter';

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: accent,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: _getOnColor(accent),
        secondary: accentHover,
        onSecondary: _getOnColor(accentHover),
        error: danger,
        onError: _getOnColor(danger),
        surface: surface,
        onSurface: textPrimary,
      ),
      textTheme: _buildTextTheme(textPrimary, textSecondary, textMuted, headingFont, bodyFont),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusValue),
          side: BorderSide(color: border, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _getOnColor(accent),
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: 24 * spacingScale,
            vertical: 12 * spacingScale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusValue * 0.75),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusValue * 0.75),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 0.5,
        space: 1,
      ),
    );
  }

  /// Get just the ColorScheme for inline use.
  static ColorScheme colorScheme(ThemeTokenSet tokens, {bool isDark = false}) {
    final accent = _parseColor(tokens.accent, const Color(0xFF6C4FD1));
    final secondary = _parseColor(tokens.accentHover, accent);
    return ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: _getOnColor(accent),
      secondary: secondary,
      onSecondary: _getOnColor(secondary),
      error: _parseColor(tokens.danger, const Color(0xFFE15361)),
      onError: Colors.white,
      surface: _parseColor(tokens.surfaceSolid, Colors.white),
      onSurface: _parseColor(tokens.textPrimary, Colors.black87),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;

    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.startsWith('rgba') || h.startsWith('rgb')) return fallback;

    // Support the common CSS hex forms #RGB, #RGBA, #RRGGBB and #RRGGBBAA.
    if (h.length == 3 || h.length == 4) {
      h = h.split('').map((c) => '$c$c').join();
    }
    if (h.length == 6) h = 'FF$h';
    if (h.length == 8) {
      // Flutter's Color integer representation is AARRGGBB while CSS's
      // 8-digit form is RRGGBBAA.
      h = '${h.substring(6, 8)}${h.substring(0, 6)}';
    } else {
      return fallback;
    }

    try {
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static bool _isDarkColor(Color color) {
    return color.computeLuminance() < 0.5;
  }

  static Color _getOnColor(Color bg) {
    return _isDarkColor(bg) ? Colors.white : Colors.black87;
  }

  static double _parseBorderRadius(String? radius) {
    switch (radius) {
      case 'small': return 6.0;
      case 'large': return 16.0;
      case 'medium':
      default: return 10.0;
    }
  }

  static TextTheme _buildTextTheme(
    Color primary, Color secondary, Color muted,
    String headingFont, String bodyFont,
  ) {
    return TextTheme(
      displayLarge: TextStyle(fontFamily: headingFont, color: primary, fontSize: 28, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(fontFamily: headingFont, color: primary, fontSize: 24, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(fontFamily: headingFont, color: primary, fontSize: 20, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(fontFamily: headingFont, color: primary, fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontFamily: bodyFont, color: primary, fontSize: 16, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(fontFamily: bodyFont, color: primary, fontSize: 16),
      bodyMedium: TextStyle(fontFamily: bodyFont, color: secondary, fontSize: 14),
      bodySmall: TextStyle(fontFamily: bodyFont, color: muted, fontSize: 12),
      labelLarge: TextStyle(fontFamily: bodyFont, color: primary, fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontFamily: bodyFont, color: muted, fontSize: 11),
    );
  }
}
