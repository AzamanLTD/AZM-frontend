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
  // Master Sprint v2 (2026-05-27): the theme catalogue is intentionally
  // small. Three identities, each with a strong, distinct character:
  //   • light    — clean white surface with deep navy text + gold accent (default)
  //   • dark     — the canonical Binance-tier dark UI
  //   • midnight — deep blackout with violet accent for night-shift use
  //
  // The previous catalogue (cyberBlue, mars, saturn, snow, neonTokyo,
  // deepOcean, volcanic, aurora, system) was retired because they all
  // resolved as colour filters on top of the same widget tree, which
  // produced an "AI-built generic" feel instead of a real visual
  // identity. We migrate any persisted index to one of the three
  // canonical values in `_loadSavedTheme` so users on those old indices
  // don't crash on app launch.
  light,
  dark,
  midnight,
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

    // Migrate old indices. The previous catalogue had 12 themes; we now
    // have 3 (light=0, dark=1, midnight=2). Anything outside that range
    // maps to light so the user lands on the default after upgrade.
    final clamped = (savedIndex >= 0 && savedIndex < AzamanTheme.values.length)
        ? savedIndex
        : 0;
    _currentTheme = AzamanTheme.values[clamped];
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
        return AzamanColors(
          isDark: false,
          name: "Light",
          icon: Icons.wb_sunny_outlined,
          background: const Color(0xFFFAFAFB),
          surface: Colors.white,
          card: const Color(0xFFFFFFFF),
          softSurface: const Color(0xFFF1F1F3),
          divider: const Color(0xFFE6E6E9),
          accent: const Color(0xFFB8860B),       // darker gold reads on white
          accentSecondary: const Color(0xFF8B6914),
          accentSurface: const Color(0xFFFDF6E3),
          success: const Color(0xFF018C5C),       // darker green on white
          danger: const Color(0xFFD32C44),
          warning: const Color(0xFFC78A00),
          textPrimary: const Color(0xFF111827),    // near-black, AA contrast on white
          textSecondary: const Color(0xFF374151),
          textTertiary: const Color(0xFF6B7280),
          glow: const Color(0xFFB8860B),
          scaffoldBackground: const Color(0xFFFAFAFB),
          border: const Color(0xFFE6E6E9),
        );

      case AzamanTheme.dark:
        // Backlog item 11 -- full intentional dark mode redesign
        // (2026-07-06). The previous palette had three real, measurable
        // defects that made "dark mode" feel like a flat filter instead
        // of a designed theme:
        //   1. `card` was byte-for-byte identical to `surface` -- so
        //      elevated cards never actually read as elevated above the
        //      screens they sat on. Now there's a real 3-step ramp:
        //      background (deepest) -> surface -> card (most elevated).
        //   2. `warning` was byte-for-byte identical to `accentSecondary`
        //      -- a warning chip and a plain secondary-accent button were
        //      visually the same color, losing all semantic meaning.
        //      Warning is now its own distinct amber-orange.
        //   3. `glow` was byte-for-byte identical to `accent` -- every
        //      "glow" halo/border effect (used 40+ places across the app)
        //      was just the flat accent color re-used, so nothing ever
        //      actually *glowed*. `glow` is now a lighter, luminous gold
        //      that reads as a genuine radiant highlight at low opacity.
        // The accent itself is warmed and brightened slightly so it pops
        // harder against the deeper background -- since every screen
        // pulls from these same tokens, this single palette change
        // carries the redesign across buttons, badges, borders and
        // accents app-wide for free.
        return AzamanColors(
          isDark: true,
          name: "Dark",
          icon: Icons.dark_mode_outlined,
          background: const Color(0xFF0A0D11),
          surface: const Color(0xFF151A20),
          card: const Color(0xFF1D232B),
          softSurface: const Color(0xFF11151B),
          divider: Colors.white.withValues(alpha: 0.07),
          accent: const Color(0xFFE3BE58),
          accentSecondary: const Color(0xFFF4B93D),
          accentSurface: const Color(0xFFE3BE58).withValues(alpha: 0.10),
          success: const Color(0xFF1CDB94),
          danger: const Color(0xFFFF5C72),
          warning: const Color(0xFFFFA726),
          textPrimary: Colors.white,
          textSecondary: Colors.white70,
          textTertiary: Colors.white38,
          glow: const Color(0xFFF5D580),
          scaffoldBackground: const Color(0xFF0A0D11),
          border: Colors.white.withValues(alpha: 0.08),
        );

      case AzamanTheme.midnight:
        return AzamanColors(
          isDark: true,
          name: "Midnight",
          icon: Icons.dark_mode_outlined,
          // True blackout — almost zero ambient light. Violet accent so
          // numbers and CTAs read with weight against pitch black.
          background: const Color(0xFF000000),
          surface: const Color(0xFF0A0612),
          card: const Color(0xFF0F0820),
          softSurface: const Color(0xFF0A0614),
          divider: const Color(0xFFBB86FC).withValues(alpha: 0.08),
          accent: const Color(0xFFBB86FC),
          accentSecondary: const Color(0xFFE040FB),
          accentSurface: const Color(0xFFBB86FC).withValues(alpha: 0.06),
          success: const Color(0xFF69F0AE),
          danger: const Color(0xFFFF5252),
          warning: const Color(0xFFFFAB40),
          textPrimary: const Color(0xFFF3E5F5),
          textSecondary: const Color(0xFFCE93D8),
          textTertiary: const Color(0xFF9C27B0).withValues(alpha: 0.55),
          glow: const Color(0xFFBB86FC),
          scaffoldBackground: const Color(0xFF000000),
          border: const Color(0xFFBB86FC).withValues(alpha: 0.08),
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
