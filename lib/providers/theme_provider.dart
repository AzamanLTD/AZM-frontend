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
  //   • light    — clean white surface with deep navy text + gold accent
  //   • dark     — the canonical Binance-tier dark UI (default)
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
  AzamanTheme _currentTheme = AzamanTheme.dark;
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
    final savedIndex = prefs.getInt('azaman_theme') ?? 1; // Default: dark

    // Migrate old indices. The previous catalogue had 12 themes; we now
    // have 3 (light=0, dark=1, midnight=2). Anything outside that range
    // maps to dark so the user lands on a sensible default after upgrade.
    final clamped = (savedIndex >= 0 && savedIndex < AzamanTheme.values.length)
        ? savedIndex
        : 1;
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

  /// Load theme from backend preferences (cross-device sync).
  /// Call after successful authentication to restore the user's theme
  /// from the server. Falls back to local SharedPreferences if the
  /// backend call fails.
  Future<void> loadFromBackend() async {
    try {
      final response = await apiClient.get('/users/preferences');
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          final themeStr = data['theme'] as String?;
          if (themeStr != null && themeStr.isNotEmpty) {
            final resolved = _themeFromString(themeStr);
            if (resolved != null && resolved != _currentTheme) {
              _currentTheme = resolved;
              notifyListeners();
              // Also persist locally so offline launches use the same theme
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt('azaman_theme', resolved.index);
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal: if backend is unreachable, keep local theme
    }
  }

  /// Parse a theme string name (e.g. "mars", "neonTokyo") to AzamanTheme.
  AzamanTheme? _themeFromString(String name) {
    for (final t in AzamanTheme.values) {
      if (t.name == name) return t;
    }
    return null;
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
          if (states.contains(WidgetState.selected)) return c.success.withOpacity(0.3);
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
          borderSide: BorderSide(color: c.accent.withOpacity(0.5)),
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
          icon: Icons.wb_sunny_rounded,
          background: const Color(0xFFF5F5F7),
          surface: Colors.white,
          card: const Color(0xFFFFFFFF),
          divider: const Color(0xFFD8D8DC),
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
        );

      case AzamanTheme.dark:
        return AzamanColors(
          isDark: true,
          name: "Dark",
          icon: Icons.dark_mode_rounded,
          background: const Color(0xFF0B0E11),
          surface: const Color(0xFF1E2329),
          card: const Color(0xFF1E2329),
          divider: Colors.white.withOpacity(0.06),
          accent: const Color(0xFFD4AF37),
          accentSecondary: const Color(0xFFF0B90B),
          accentSurface: const Color(0xFFD4AF37).withOpacity(0.08),
          success: const Color(0xFF02C076),
          danger: const Color(0xFFF6465D),
          warning: const Color(0xFFF0B90B),
          textPrimary: Colors.white,
          textSecondary: Colors.white70,
          textTertiary: Colors.white38,
          glow: const Color(0xFFD4AF37),
        );

      case AzamanTheme.midnight:
        return AzamanColors(
          isDark: true,
          name: "Midnight",
          icon: Icons.bedtime_rounded,
          // True blackout — almost zero ambient light. Violet accent so
          // numbers and CTAs read with weight against pitch black.
          background: const Color(0xFF000000),
          surface: const Color(0xFF0A0612),
          card: const Color(0xFF0F0820),
          divider: const Color(0xFFBB86FC).withOpacity(0.08),
          accent: const Color(0xFFBB86FC),
          accentSecondary: const Color(0xFFE040FB),
          accentSurface: const Color(0xFFBB86FC).withOpacity(0.06),
          success: const Color(0xFF69F0AE),
          danger: const Color(0xFFFF5252),
          warning: const Color(0xFFFFAB40),
          textPrimary: const Color(0xFFF3E5F5),
          textSecondary: const Color(0xFFCE93D8),
          textTertiary: const Color(0xFF9C27B0).withOpacity(0.55),
          glow: const Color(0xFFBB86FC),
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

  const AzamanColors({
    required this.isDark,
    required this.name,
    required this.icon,
    required this.background,
    required this.surface,
    required this.card,
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
  });
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
