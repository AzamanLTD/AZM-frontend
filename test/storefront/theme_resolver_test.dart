// =============================================================================
// Phase 9: Storefront Theme Resolver Tests
//
// Verifies hex/rgba color parsing, fallback behavior, and dark/light detection.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman_frontend/storefront/core/storefront_theme_resolver.dart';
import 'package:azaman_frontend/storefront/models/storefront_models.dart';

void main() {
  group('StorefrontThemeResolver — Color Parsing', () {
    test('resolves 6-digit hex colors correctly', () {
      final tokens = ThemeTokenSet(
        accent: '#B8860B',
        textPrimary: '#111827',
      );
      final scheme = StorefrontThemeResolver.colorScheme(tokens);
      expect(scheme.primary, const Color(0xFFB8860B));
      expect(scheme.onSurface, const Color(0xFF111827));
    });

    test('resolves 3-digit hex colors correctly', () {
      final tokens = ThemeTokenSet(accent: '#F0A');
      final scheme = StorefrontThemeResolver.colorScheme(tokens);
      expect(scheme.primary, const Color(0xFFFF00AA));
    });

    test('handles null/empty values with fallback', () {
      final tokens = ThemeTokenSet(accent: null, textPrimary: '');
      final scheme = StorefrontThemeResolver.colorScheme(tokens);
      // Falls back to default accent
      expect(scheme.primary, const Color(0xFF6C4FD1));
    });

    test('rejects rgba strings and uses fallback', () {
      final tokens = ThemeTokenSet(accent: 'rgba(255,255,255,0.07)');
      final scheme = StorefrontThemeResolver.colorScheme(tokens);
      // rgba is not parsed — fallback used
      expect(scheme.primary, const Color(0xFF6C4FD1));
    });
  });

  group('StorefrontThemeResolver — ThemeData Building', () {
    test('builds a complete ThemeData from a storefront theme', () {
      final theme = StorefrontThemeInfo(
        id: 'theme-1',
        key: 'classic_light',
        name: 'Classic Light',
        tokenSet: ThemeTokenSet(
          accent: '#6C4FD1',
          background: '#F7F5F2',
          textPrimary: '#15141A',
        ),
        borderRadius: 'medium',
        spacingScale: 1.0,
        typography: {'heading': 'Inter', 'body': 'Inter'},
      );

      final data = StorefrontThemeResolver.resolve(theme);
      expect(data.useMaterial3, isTrue);
      expect(data.primaryColor, const Color(0xFF6C4FD1));
      expect(data.scaffoldBackgroundColor, const Color(0xFFF7F5F2));
    });

    test('detects dark theme from background color', () {
      final theme = StorefrontThemeInfo(
        id: 'theme-2',
        key: 'midnight',
        name: 'Midnight',
        tokenSet: ThemeTokenSet(
          accent: '#7C5CFF',
          background: '#0F0E13',
          textPrimary: '#F0F0F5',
        ),
        borderRadius: 'large',
        spacingScale: 1.0,
      );

      final data = StorefrontThemeResolver.resolve(theme);
      expect(data.brightness, Brightness.dark);
    });

    test('uses small border radius when specified', () {
      final theme = StorefrontThemeInfo(
        id: 'theme-3',
        key: 'compact',
        name: 'Compact',
        tokenSet: ThemeTokenSet(accent: '#FF0000'),
        borderRadius: 'small',
        spacingScale: 1.0,
      );

      final data = StorefrontThemeResolver.resolve(theme);
      // Card should have small radius (6.0)
      final shape = data.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(6.0));
    });
  });
}
