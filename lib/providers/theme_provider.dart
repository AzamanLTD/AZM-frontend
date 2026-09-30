import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/services/api_client.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/utils/azaman_page_transitions.dart';


// ============================================================
// AZAMAN THEME ENGINE — V5
//
// Two brightnesses (light / dark) × four accent identities
// (gold / teal / indigo / rose). The SURFACE ladder is shared by
// all eight combinations; only the accent family changes. That is
// deliberate: a user picking an identity must never get a
// different contrast contract, and no screen needs eight sets of
// visual QA.
//
// TASK-025 also lets a Marketplace vertical borrow the accent for
// the duration of a session (see AzVerticalAccentScope), so being
// in Restaurants looks different from being in Hotels without the
// user managing another theme.
//
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

/// The four accent identities. Surfaces never change; only the accent family does.
enum AzAccent { gold, teal, indigo, rose }

/// One accent family in both brightnesses.
///
/// `onAccent` is part of the contract, not an afterthought: gold on white needs
/// dark ink, indigo on black needs white ink. Getting this wrong is how a "theme
/// picker" ships unreadable buttons.
class AzAccentFamily {
  final AzAccent id;
  final Color lightAccent;
  final Color lightOnAccent;
  final Color lightSecondary;
  final Color darkAccent;
  final Color darkOnAccent;
  final Color darkSecondary;

  const AzAccentFamily({
    required this.id,
    required this.lightAccent,
    required this.lightOnAccent,
    required this.lightSecondary,
    required this.darkAccent,
    required this.darkOnAccent,
    required this.darkSecondary,
  });

  Color accentFor(bool isDark) => isDark ? darkAccent : lightAccent;
  Color onAccentFor(bool isDark) => isDark ? darkOnAccent : lightOnAccent;
  Color secondaryFor(bool isDark) => isDark ? darkSecondary : lightSecondary;

  static const Map<AzAccent, AzAccentFamily> all = {
    AzAccent.gold: AzAccentFamily(
      id: AzAccent.gold,
      lightAccent: Color(0xFFB8860B),
      lightOnAccent: Colors.white,
      lightSecondary: Color(0xFF8B6914),
      darkAccent: Color(0xFFE0AE3A),
      darkOnAccent: Colors.black,
      darkSecondary: Color(0xFFF59E0B),
    ),
    AzAccent.teal: AzAccentFamily(
      id: AzAccent.teal,
      lightAccent: Color(0xFF0E7C7B),
      lightOnAccent: Colors.white,
      lightSecondary: Color(0xFF0F766E),
      darkAccent: Color(0xFF2DD4BF),
      darkOnAccent: Colors.black,
      darkSecondary: Color(0xFF5EEAD4),
    ),
    AzAccent.indigo: AzAccentFamily(
      id: AzAccent.indigo,
      lightAccent: Color(0xFF4338CA),
      lightOnAccent: Colors.white,
      lightSecondary: Color(0xFF3730A3),
      darkAccent: Color(0xFF8B9BFF),
      darkOnAccent: Colors.black,
      darkSecondary: Color(0xFFA5B4FC),
    ),
    AzAccent.rose: AzAccentFamily(
      id: AzAccent.rose,
      lightAccent: Color(0xFFBE123C),
      lightOnAccent: Colors.white,
      lightSecondary: Color(0xFF9F1239),
      darkAccent: Color(0xFFFB7185),
      darkOnAccent: Colors.black,
      darkSecondary: Color(0xFFFDA4AF),
    ),
  };
}

class ThemeProvider with ChangeNotifier {
  AzamanTheme _currentTheme = AzamanTheme.light;
  AzAccent _accent = AzAccent.gold;
  bool _isLoaded = false;

  /// Set in [dispose]. Async work started in the constructor (SharedPreferences
  /// read) or by a pending [setTheme] can resolve after the provider has been
  /// torn down; notifying listeners then throws.
  bool _isDisposed = false;

  AzamanTheme get currentTheme => _currentTheme;
  AzAccent get accent => _accent;
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
    // TASK-025: load the persisted accent identity (azaman_accent).
    // Invalid/missing/out-of-range values must safely fall back to gold —
    // the picker's default identity.
    final savedAccentIndex = prefs.getInt('azaman_accent');
    if (savedAccentIndex != null &&
        savedAccentIndex >= 0 &&
        savedAccentIndex < AzAccent.values.length) {
      _accent = AzAccent.values[savedAccentIndex];
    } else {
      _accent = AzAccent.gold;
    }
    _isLoaded = true;
    if (_isDisposed) return;
    notifyListeners();
  }

  /// TASK-025: choose the accent identity (gold / teal / indigo / rose).
  ///
  /// Local-only persistence — the accent is NOT backend-synced: the theme
  /// sync already covers cross-device feel, and an accent flip must never
  /// wait on (or fail because of) a network round-trip. Opening a vertical
  /// never touches this value either; vertical borrows are session-only.
  Future<void> setAccent(AzAccent accent) async {
    _accent = accent;
    if (_isDisposed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('azaman_accent', accent.index);
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> setTheme(AzamanTheme theme) async {
    _currentTheme = theme;
    if (_isDisposed) return;
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
    } catch (e) {
      // Non-fatal: backend sync failure should never affect local UX, but it
      // must stay diagnosable in debug builds.
      debugPrint('ThemeProvider: theme sync to backend failed: $e');
    }
  }

  /// Push the local theme to the backend when the server has no preference.
  /// Local SharedPreferences is the source of truth; we never override the
  /// active theme from the server so new installs always start in light mode.
  Future<void> loadFromBackend() async {
    try {
      final response = await apiClient.get('/users/preferences');
      // A non-200 is a normal answer (offline, unauthenticated, no preference
      // stored). Log it rather than returning silently, because "the backend
      // never had my theme" and "the request was rejected" are very different
      // bugs and today they look identical in the field.
      if (response.statusCode != 200) {
        debugPrint(
          'ThemeProvider: loadFromBackend got status '
          '${response.statusCode} for /users/preferences — keeping local theme.',
        );
        return;
      }

      final themeStr = _themeNameFromResponseBody(response.body);
      if (themeStr == null) {
        // The server has no usable preference stored: push the local one so
        // the next device signs in with the theme the user actually chose.
        await _syncToBackend(_currentTheme);
      }
    } catch (e) {
      // Non-fatal, but a swallowed error here is impossible to diagnose later.
      debugPrint('ThemeProvider: loadFromBackend failed: $e');
    }
  }

  /// Parses a `/users/preferences` body and returns the stored theme name, or
  /// `null` when the body is absent, unparseable, not an object, or carries no
  /// usable string theme.
  ///
  /// Everything downstream reads fields through pattern matching against
  /// `Map<String, dynamic>` rather than casting the decoded value directly: a
  /// 200 is not a guarantee of shape. Proxies, gateways and maintenance pages
  /// return HTML or an empty body, and a `data` key can legitimately hold a
  /// list or a bare string. Each of those must degrade to "no stored
  /// preference" instead of throwing a `TypeError` that gets swallowed by the
  /// caller's catch — a bare cast is exactly what turns a diagnosable response
  /// into silence.
  static String? _themeNameFromResponseBody(String body) {
    if (body.trim().isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }

    return switch (decoded) {
      // Shape: {"data": {"theme": "dark"}}
      {'data': final Map<String, dynamic> data} =>
        switch (data['theme']) {
          final String theme when theme.isNotEmpty => theme,
          _ => null,
        },
      // Shape: {"theme": "dark"} — some deployments unwrap `data` already.
      {'theme': final String theme} when theme.isNotEmpty => theme,
      _ => null,
    };
  }

  // --- QUICK ACCESSORS FOR WIDGETS ---
  //
  // Accent-aware: every instance consumer (shell, widgets, settings) sees
  // the user's selected identity. The STATIC getThemeData(theme) /
  // getColors(theme) remain the historical baseline so existing callers and
  // the TASK-004 permanent guard keep their exact visuals.
  ThemeData get themeData => getThemeData(_currentTheme, accent: _accent);
  AzamanColors get colors => getColors(_currentTheme).withAccent(_accent);

  // ============================================================
  // THEME DEFINITIONS
  // ============================================================

  /// TASK-025: `accent == null` (every pre-existing static call) keeps the
  /// historical visual identity per theme — light gold / dark teal — so
  /// `test/theme/theme_provider_test.dart` and all static callers keep their
  /// exact current visuals. Passing an explicit [accent] resolves it through
  /// the accent family. The INSTANCE getters always pass the user's accent.
  static ThemeData getThemeData(AzamanTheme theme, {AzAccent? accent}) {
    final c = accent == null ? getColors(theme) : getColors(theme).withAccent(accent);
    // Derived once and threaded through both ThemeData and its ColorScheme so
    // the two can never disagree about which mode the palette is in.
    final brightness = brightnessOf(c);

    return _buildComponentTheme(c, brightness).copyWith(
      brightness: brightness,
      primaryColor: c.accent,
      // Transparent so the ThemedAppBackdrop gradient shows through every
      // Scaffold. Screens that explicitly set backgroundColor: ... still
      // win, but the default is now "let the theme breathe."
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.background,
      // fontFamily is set in _buildComponentTheme — ThemeData.copyWith has no
      // such parameter, so it cannot be layered on here.
      // TASK-004 — AzText type scale becomes the app-wide text theme so
      // every widget inherits the premium scale instead of Material defaults.
      textTheme: AzText.theme().apply(
        bodyColor: c.textPrimary,
        displayColor: c.textPrimary,
      ),
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
      colorScheme: buildColorScheme(c, brightness),
    );
  }

  /// Component-level themes (app bar, cards, buttons, inputs, ...) for the
  /// given palette. Returned as a [ThemeData] shell that [getThemeData] layers
  /// the global concerns (brightness, colours, text, transitions) on top of via
  /// `copyWith`, so the top-level builder stays short and readable.
  ///
  /// Split out of [getThemeData] so component theming can be read, reviewed and
  /// changed without wading through the global concerns. Private because
  /// callers go through [getThemeData], which supplies [brightness] from the
  /// palette so the two cannot disagree.
  static ThemeData _buildComponentTheme(AzamanColors c, Brightness brightness) {
    return ThemeData(
      fontFamily: 'Inter', // bundled locally — see pubspec.yaml fonts: section
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
        // Accent-driven (not success-green): a switch means "on/off" for the
        // user, and the teal/amber accent is the brand's 'live/active' signal.
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent;
          return c.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.accent.withValues(alpha: 0.3);
          return c.divider;
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          // Brightness-derived rather than c.isDark, so a caller that passes a
          // mismatched pair cannot produce a half-light component theme.
          foregroundColor: brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
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
    );
  }

  /// The one place the theme's brightness is derived from the palette.
  static Brightness brightnessOf(AzamanColors c) =>
      c.isDark ? Brightness.dark : Brightness.light;

  /// The complete M3 [ColorScheme] bridge.
  ///
  /// Material widgets (DatePicker, Tooltip, Stepper, ProgressIndicator, ...)
  /// read roles straight from the `ColorScheme`. Leaving a role unset makes
  /// the framework substitute its own baseline palette (a purple/lavender
  /// default), which is why framework-rendered surfaces used to look foreign
  /// next to Azaman's own palette. Every role below is derived from
  /// [AzamanColors] so no framework colour can leak in.
  ///
  /// Kept in its own method so role coverage can be reviewed (and tested) as
  /// one list rather than being buried in the middle of a ThemeData literal.
  /// `test/theme/theme_provider_test.dart` asserts each of these.
  ///
  /// [brightness] is passed in by [getThemeData] so it matches the ThemeData's
  /// own brightness; when omitted it is derived from [c] via [brightnessOf].
  ///
  /// Built from [ColorScheme.fromSeed] and then overridden, rather than
  /// constructed from the bare `ColorScheme(...)` constructor. The constructor
  /// requires every role by hand: a role Material adds in a future SDK is
  /// silently absent and falls back to Flutter's *baseline* palette (the
  /// purple/lavender defaults this whole method exists to eliminate).
  /// `fromSeed` guarantees a complete, seed-derived scheme, and the
  /// `copyWith` below then pins the roles Azaman owns to real palette values.
  /// Anything Material adds later therefore arrives seed-derived (gold/teal
  /// tonal palette) instead of purple.
  static ColorScheme buildColorScheme(AzamanColors c, [Brightness? brightness]) {
    final resolved = brightness ?? brightnessOf(c);

    return ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: resolved,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.isDark ? Colors.black : Colors.white,
      primaryContainer: c.accentSurface,
      onPrimaryContainer: c.textPrimary,
      inversePrimary: c.accentSecondary,
      secondary: c.accentSecondary,
      onSecondary: c.isDark ? Colors.black : Colors.white,
      secondaryContainer: c.accentSurface,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.accent,
      onTertiary: c.isDark ? Colors.black : Colors.white,
      // NOT `c.danger`: the error ramp is a fixed Material semantic (red
      // across themes). Seeding it from the accent would let a brand change
      // silently repaint every "something went wrong" state.
      error: c.danger,
      onError: Colors.white,
      errorContainer: c.danger.withValues(alpha: 0.16),
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceDim: c.background,
      surfaceBright: c.card,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.background,
      surfaceContainer: c.softSurface,
      surfaceContainerHigh: c.softSurface,
      surfaceContainerHighest: c.card,
      surfaceTint: c.accent,
      inverseSurface: c.isDark ? Colors.white : Colors.black,
      onInverseSurface: c.isDark ? Colors.black : Colors.white,
      outline: c.border,
      outlineVariant: c.divider,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
    );
  }

  /// Shared baseline every palette starts from. Each case below only has to
  /// declare what actually differs, so renaming or re-tuning a field is a
  /// one-line change instead of a 20-line duplicated literal.
  static const AzamanColors _paletteDefaults = AzamanColors(
    isDark: false,
    name: "Light",
    icon: Icons.wb_sunny_outlined,
    background: Color(0xFFFAFAFB),
    surface: Colors.white,
    card: Color(0xFFFFFFFF),
    softSurface: Color(0xFFF1F1F3),
    divider: Color(0xFFE6E6E9),
    accent: Color(0xFFB8860B),
    accentSecondary: Color(0xFF8B6914),
    accentSurface: Color(0xFFFDF6E3),
    success: Color(0xFF018C5C),
    danger: Color(0xFFD32C44),
    warning: Color(0xFFC78A00),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF374151),
    textTertiary: Color(0xFF6B7280),
    glow: Color(0xFFB8860B),
    scaffoldBackground: Color(0xFFFAFAFB),
    border: Color(0xFFE6E6E9),
  );

  static AzamanColors getColors(AzamanTheme theme) {
    switch (theme) {
      case AzamanTheme.light:
        return _paletteDefaults;

      case AzamanTheme.dark:
        // Only the deltas below differ from [_paletteDefaults].
        // V4 redesign (2026-08-15): True black background with
        // teal/emerald primary accent — deliberately NOT the gold-on-black
        // Binance palette. Amber stays as a secondary accent for warmth.
        //   background: #000000 (true black, not dark gray)
        //   accent: #2DD4BF (teal — fresh, modern, distinctly non-Binance)
        //   accentSecondary: #F59E0B (amber — provides warmth without gold-dominance)
        // 3-step elevation ramp: background → surface → card.
        return _paletteDefaults.copyWith(
          isDark: true,
          name: "Dark",
          icon: Icons.dark_mode_outlined,
          background: const Color(0xFF000000),
          surface: const Color(0xFF0A0A0A),
          card: const Color(0xFF161616),
          softSurface: const Color(0xFF0F0F0F),
          divider: const Color(0x12FFFFFF),       // white @ 7%
          accent: const Color(0xFF2DD4BF),         // teal — primary CTA color
          accentSecondary: const Color(0xFFF59E0B), // amber — warm secondary
          accentSurface: const Color(0x1A2DD4BF),  // teal @ 10%
          success: const Color(0xFF34D399),
          danger: const Color(0xFFF87171),
          warning: const Color(0xFFFBBF24),
          textPrimary: Colors.white,
          textSecondary: Colors.white70,
          textTertiary: Colors.white38,
          glow: const Color(0xFF2DD4BF),           // luminous teal glow
          scaffoldBackground: const Color(0xFF000000),
          border: const Color(0x14FFFFFF),          // white @ 8%
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

  /// Returns a copy with only the supplied fields replaced; every omitted
  /// field keeps its current value. Used by [ThemeProvider.getColors] so each
  /// palette only declares what differs from the shared defaults.
  AzamanColors copyWith({
    bool? isDark,
    String? name,
    IconData? icon,
    Color? background,
    Color? surface,
    Color? card,
    Color? softSurface,
    Color? divider,
    Color? accent,
    Color? accentSecondary,
    Color? accentSurface,
    Color? success,
    Color? danger,
    Color? warning,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? glow,
    Color? scaffoldBackground,
    Color? border,
  }) {
    return AzamanColors(
      isDark: isDark ?? this.isDark,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      softSurface: softSurface ?? this.softSurface,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentSurface: accentSurface ?? this.accentSurface,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      glow: glow ?? this.glow,
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      border: border ?? this.border,
    );
  }

  // Aliases used by business_reviews_section.dart
  Color get commentPrimary => textPrimary;
  Color get commentSecondary => textSecondary;
  Color get commentTertiary => textTertiary;

  /// TASK-025: ink that stays readable on the active accent. Part of the
  /// accent contract, not an afterthought — gold on white needs dark ink,
  /// indigo on black needs white ink.
  Color get onAccent => isDark ? Colors.black : Colors.white;

  /// TASK-025: the same surface ladder with a different accent family.
  ///
  /// Purely additive: the constructor is untouched, and every non-accent
  /// field (surfaces, semantic colours, text ladder, borders) is carried
  /// over unchanged. Only `accent`, `accentSecondary`, `accentSurface` and
  /// `glow` change — exactly the fields an identity owns.
  AzamanColors withAccent(AzAccent accent) {
    final family =
        AzAccentFamily.all[accent] ?? AzAccentFamily.all[AzAccent.gold]!;
    final nextAccent = family.accentFor(isDark);
    return AzamanColors(
      isDark: isDark,
      name: '$name · ${accent.name}',
      icon: icon,
      background: background,
      surface: surface,
      card: card,
      softSurface: softSurface,
      divider: divider,
      accent: nextAccent,
      accentSecondary: family.secondaryFor(isDark),
      accentSurface: nextAccent.withValues(alpha: 0.10),
      success: success,
      danger: danger,
      warning: warning,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      glow: nextAccent,
      scaffoldBackground: scaffoldBackground,
      border: border,
    );
  }
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
