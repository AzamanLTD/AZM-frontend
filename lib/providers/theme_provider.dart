import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/utils/azaman_page_transitions.dart';


// ============================================================
// AZAMAN THEME ENGINE — V3 (Immersive Planetary Themes)
//
// 11 distinct visual identities that transform the ENTIRE app.
// Each theme defines colors, glow effects, card styles, and mood.
// Persists across app restarts via SharedPreferences.
// ============================================================

enum AzamanTheme {
  // V4 (2026-08-15): Two identities only. The midnight/purple theme was
  // removed per founder request — the dark theme is now the true-black
  // night experience.
  //   • light — clean white surface with deep navy text + gold accent (default)
  //   • dark  — true black with teal/emerald accent (NOT gold, NOT Binance)
  light,
  dark,
}

class ThemeProvider with ChangeNotifier {
  AzamanTheme _currentTheme = AzamanTheme.light;
  bool _isLoaded = false;

  AzamanTheme get currentTheme => _currentTheme;
  bool get isLoaded => _isLoaded;

  /// Backwards-compat shim — older call sites read `resolvedTheme` to
  /// resolve the now-removed `system` mode. With the catalogue trimmed to
  /// three explicit themes, resolved == current.
  AzamanTheme get resolvedTheme => _currentTheme;

  ThemeProvider() {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt('azaman_theme') ?? 0; // Default

    // Migration: midnight (old index 2) → dark (new index 1).
    // Anything else outside range → light (default).
    if (savedIndex == 2) {
      _currentTheme = AzamanTheme.dark;
    } else if (savedIndex >= 0 && savedIndex < AzamanTheme.values.length) {
      _currentTheme = AzamanTheme.values[savedIndex];
    } else {
      _currentTheme = AzamanTheme.light;
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setTheme(AzamanTheme theme) async {
    _currentTheme = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('azaman_theme', theme.index);
    // Fire-and-forget sync to backend for cross-device persistence
    _syncToBackend(theme);
  }

  /// Sync theme choice to backend (fire-and-forget, never blocks UI).
  /// Called automatically on every setTheme() call.
  Future<void> _syncToBackend(AzamanTheme theme) async {
    try {
      await apiClient.put('/users/preferences/theme', {
        'theme': theme.name,
      });
    } catch (_) {
      // Non-fatal: backend sync failure should never affect local UX
    }
  }

  /// Push the local theme to the backend when the server has no preference.
  /// Local SharedPreferences is the source of truth; we never override the
  /// active theme from the server so new installs always start in light mode.
  Future<void> loadFromBackend() async {
    try {
      final response = await apiClient.get('/users/preferences');
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body);
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final themeStr = data['theme'] as String?;
      if (themeStr == null || themeStr.isEmpty) {
        await _syncToBackend(_currentTheme);
      }
    } catch (_) {
    }
  }

  // --- QUICK ACCESSORS FOR WIDGETS ---
  ThemeData get themeData => getThemeData(_currentTheme);
  AzamanColors get colors => getColors(_currentTheme);

  // ============================================================
  // THEME DEFINITIONS
  // ============================================================

  static ThemeData getThemeData(AzamanTheme theme) {
    final c = getColors(theme);

    return ThemeData(
      brightness: c.isDark ? Brightness.dark : Brightness.light,
      primaryColor: c.accent,
      // Transparent so the ThemedAppBackdrop gradient shows through every
      // Scaffold. Screens that explicitly set backgroundColor: ... still
      // win, but the default is now "let the theme breathe."
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.background,
      fontFamily: GoogleFonts.inter().fontFamily,
      // Phase H — single cohesive slide+fade transition for every Navigator.push,
      // applied via PageTransitionsTheme so existing imperative MaterialPageRoute
      // calls scattered across the app pick it up automatically.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: AzamanPageTransitionsBuilder(),
          TargetPlatform.iOS: AzamanPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AzamanPageTransitionsBuilder(),
          TargetPlatform.linux: AzamanPageTransitionsBuilder(),
          TargetPlatform.macOS: AzamanPageTransitionsBuilder(),
          TargetPlatform.windows: AzamanPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      cardColor: c.card,
      dividerColor: c.divider,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textTertiary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.card,
        contentTextStyle: TextStyle(color: c.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.success;
          return c.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.success.withValues(alpha: 0.3);
          return c.divider;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.isDark ? Colors.black : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: TextStyle(color: c.textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent.withValues(alpha: 0.5)),
        ),
      ),
      colorScheme: ColorScheme(
        brightness: c.isDark ? Brightness.dark : Brightness.light,
        primary: c.accent,
        onPrimary: c.isDark ? Colors.black : Colors.white,
        secondary: c.accentSecondary,
        onSecondary: Colors.white,
        error: c.danger,
        onError: Colors.white,
        surface: c.surface,
        onSurface: c.textPrimary,
      ),
    );
  }

  static AzamanColors getColors(AzamanTheme theme) {
    switch (theme) {
      case AzamanTheme.light:
        return const AzamanColors(
          isDark: false,
          name: "Light",
          icon: Icons.wb_sunny_outlined,
          background: Color(0xFFFAFAFB),
          surface: Colors.white,
          card: Color(0xFFFFFFFF),
          softSurface: Color(0xFFF1F1F3),
          divider: Color(0xFFE6E6E9),
          accent: Color(0xFFB8860B),       // darker gold reads on white
          accentSecondary: Color(0xFF8B6914),
          accentSurface: Color(0xFFFDF6E3),
          success: Color(0xFF018C5C),       // darker green on white
          danger: Color(0xFFD32C44),
          warning: Color(0xFFC78A00),
          textPrimary: Color(0xFF111827),    // near-black, AA contrast on white
          textSecondary: Color(0xFF374151),
          textTertiary: Color(0xFF6B7280),
          glow: Color(0xFFB8860B),
          scaffoldBackground: Color(0xFFFAFAFB),
          border: Color(0xFFE6E6E9),
        );

      case AzamanTheme.dark:
        // V4 redesign (2026-08-15): True black background with
        // teal/emerald primary accent — deliberately NOT the gold-on-black
        // Binance palette. Amber stays as a secondary accent for warmth.
        //   background: #000000 (true black, not dark gray)
        //   accent: #2DD4BF (teal — fresh, modern, distinctly non-Binance)
        //   accentSecondary: #F59E0B (amber — provides warmth without gold-dominance)
        // 3-step elevation ramp: background → surface → card.
        return const AzamanColors(
          isDark: true,
          name: "Dark",
          icon: Icons.dark_mode_outlined,
          background: Color(0xFF000000),
          surface: Color(0xFF0A0A0A),
          card: Color(0xFF161616),
          softSurface: Color(0xFF0F0F0F),
          divider: Color(0x12FFFFFF),       // white @ 7%
          accent: Color(0xFF2DD4BF),         // teal — primary CTA color
          accentSecondary: Color(0xFFF59E0B), // amber — warm secondary
          accentSurface: Color(0x1A2DD4BF),  // teal @ 10%
          success: Color(0xFF34D399),
          danger: Color(0xFFF87171),
          warning: Color(0xFFFBBF24),
          textPrimary: Colors.white,
          textSecondary: Colors.white70,
          textTertiary: Colors.white38,
          glow: Color(0xFF2DD4BF),           // luminous teal glow
          scaffoldBackground: Color(0xFF000000),
          border: Color(0x14FFFFFF),          // white @ 8%
        );

    }
  }
}

// ============================================================
// AZAMAN COLOR SYSTEM
// Every widget in the app should reference these instead of
// hardcoded hex values. This makes theme switching seamless.
// ============================================================
class AzamanColors {
  final bool isDark;
  final String name;
  final IconData icon;

  final Color background;
  final Color surface;
  final Color card;
  final Color softSurface;
  final Color divider;

  final Color accent;
  final Color accentSecondary;
  final Color accentSurface;

  final Color success;
  final Color danger;
  final Color warning;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color glow;
  
  final Color scaffoldBackground;
  final Color border;

  const AzamanColors({
    required this.isDark,
    required this.name,
    required this.icon,
    required this.background,
    required this.surface,
    required this.card,
    required this.softSurface,
    required this.divider,
    required this.accent,
    required this.accentSecondary,
    required this.accentSurface,
    required this.success,
    required this.danger,
    required this.warning,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.glow,
    required this.scaffoldBackground,
    required this.border,
  });

  // Aliases used by business_reviews_section.dart
  Color get commentPrimary => textPrimary;
  Color get commentSecondary => textSecondary;
  Color get commentTertiary => textTertiary;
}



// =============================================================================
// RIVERPOD HANDLE  (canonical V2 access path)
//
// Read in NEW code via:
//   final colors = ref.watch(themeProvider).colors;
//   ref.read(themeProvider).setTheme(AzamanTheme.dark);
//
// For granular reads (only repaint when colors change, not theme name etc.):
//   final colors = ref.watch(themeProvider.select((t) => t.colors));
// =============================================================================
final themeProvider = ChangeNotifierProvider<ThemeProvider>((ref) {
  return ThemeProvider();
});
