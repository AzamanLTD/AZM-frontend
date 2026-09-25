import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/storefront/core/storefront_theme_resolver.dart';
import 'package:azaman/storefront/models/storefront_models.dart';

void main() {
  group('StorefrontThemeResolver — defensive token handling', () {
    test('supports CSS #RGBA and #RRGGBBAA alpha formats', () {
      final rgba = ThemeTokenSet(accent: '#1234');
      final rrggbbaa = ThemeTokenSet(accent: '#11223344');

      expect(
        StorefrontThemeResolver.colorScheme(rgba).primary,
        const Color(0x44112233),
      );
      expect(
        StorefrontThemeResolver.colorScheme(rrggbbaa).primary,
        const Color(0x44112233),
      );
    });

    test('falls back for malformed and unsupported color tokens', () {
      final scheme = StorefrontThemeResolver.colorScheme(
        ThemeTokenSet(accent: '#12', accentHover: 'rgb(1,2,3)'),
      );

      expect(scheme.primary, const Color(0xFF6C4FD1));
      expect(scheme.secondary, const Color(0xFF6C4FD1));
      // accent #6C4FD1 is dark (luminance < 0.5), so on-color is white.
      expect(scheme.onSecondary, const Color(0xFFFFFFFF));
    });

    test('uses the secondary token when calculating onSecondary', () {
      final scheme = StorefrontThemeResolver.colorScheme(
        ThemeTokenSet(
          accent: '#FFFFFF',
          accentHover: '#000000',
        ),
      );

      expect(scheme.secondary, const Color(0xFF000000));
      expect(scheme.onSecondary, const Color(0xFFFFFFFF));
    });

    test('clamps remote spacing scale to a safe range', () {
      final small = StorefrontThemeResolver.resolve(
        StorefrontThemeInfo(
          id: 'small',
          key: 'small',
          name: 'Small',
          spacingScale: 0.01,
        ),
      );
      final large = StorefrontThemeResolver.resolve(
        StorefrontThemeInfo(
          id: 'large',
          key: 'large',
          name: 'Large',
          spacingScale: 99,
        ),
      );

      final smallPadding = small.elevatedButtonTheme.style!.padding!.resolve({})!;
      final largePadding = large.elevatedButtonTheme.style!.padding!.resolve({})!;

      // spacingScale 0.01 clamps to 0.5 → per-side 24*0.5=12 / 12*0.5=6.
      // .horizontal returns left+right, .vertical returns top+bottom.
      expect(smallPadding.horizontal, 24);
      expect(smallPadding.vertical, 12);
      // spacingScale 99 clamps to 2.0 → per-side 24*2=48 / 12*2=24.
      expect(largePadding.horizontal, 96);
      expect(largePadding.vertical, 48);
    });
  });
}
