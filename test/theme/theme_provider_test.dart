// Regression guard for the M3 ColorScheme bridge + AzText textTheme wiring
// added to ThemeProvider.getThemeData.
//
// Before this test, a framework widget (DatePicker, Tooltip, Stepper, ...)
// that reads ColorScheme roles could silently fall back to Material's default
// purple/grey palette. These assertions pin every role to its AzamanColors
// source so any future colour edit that breaks the bridge fails loudly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/theme_provider.dart';

void main() {
  for (final theme in AzamanTheme.values) {
    group('${theme.name} theme', () {
      final colors = ThemeProvider.getColors(theme);
      final data = ThemeProvider.getThemeData(theme);
      final scheme = data.colorScheme;

      test('brightness matches the palette', () {
        expect(
          data.brightness,
          colors.isDark ? Brightness.dark : Brightness.light,
        );
        expect(scheme.brightness, data.brightness);
      });

      test('accent roles map to AzamanColors', () {
        expect(scheme.primary, colors.accent);
        expect(scheme.primaryContainer, colors.accentSurface);
        expect(scheme.inversePrimary, colors.accentSecondary);
        expect(scheme.secondary, colors.accentSecondary);
        expect(scheme.secondaryContainer, colors.accentSurface);
        expect(scheme.tertiary, colors.accent);
        expect(scheme.surfaceTint, colors.accent);
      });

      test('error roles map to danger colour', () {
        expect(scheme.error, colors.danger);
        expect(scheme.errorContainer, colors.danger.withValues(alpha: 0.16));
        expect(scheme.onErrorContainer, colors.danger);
      });

      test('surface roles map to the elevation ramp', () {
        expect(scheme.surface, colors.surface);
        expect(scheme.surfaceDim, colors.background);
        expect(scheme.surfaceBright, colors.card);
        expect(scheme.surfaceContainerLowest, colors.background);
        expect(scheme.surfaceContainerLow, colors.background);
        expect(scheme.surfaceContainer, colors.softSurface);
        expect(scheme.surfaceContainerHigh, colors.softSurface);
        expect(scheme.surfaceContainerHighest, colors.card);
      });

      test('content and outline roles map to text and border colours', () {
        expect(scheme.onSurface, colors.textPrimary);
        expect(scheme.onSurfaceVariant, colors.textSecondary);
        expect(scheme.outline, colors.border);
        expect(scheme.outlineVariant, colors.divider);
      });

      test('no Material default purple leaks into the scheme', () {
        // ColorScheme defaults primary to a purple in the M3 baseline; the
        // bridge must always override it.
        expect(scheme.primary, isNot(const Color(0xFF6750A4)));
        expect(scheme.primary, isNot(const Color(0xFFD0BCFF)));
      });

      test('textTheme is present and coloured with textPrimary', () {
        expect(data.textTheme, isNotNull);
        expect(data.textTheme.bodyMedium?.color, colors.textPrimary);
        expect(data.textTheme.bodyLarge?.color, colors.textPrimary);
        expect(data.textTheme.displaySmall?.color, colors.textPrimary);
        expect(data.textTheme.titleLarge?.color, colors.textPrimary);
        expect(data.textTheme.labelSmall?.color, colors.textPrimary);
      });
    });
  }

  test('light and dark themes produce different colour schemes', () {
    final light = ThemeProvider.getThemeData(AzamanTheme.light).colorScheme;
    final dark = ThemeProvider.getThemeData(AzamanTheme.dark).colorScheme;
    expect(light.primary, isNot(dark.primary));
    expect(light.surface, isNot(dark.surface));
  });
}
