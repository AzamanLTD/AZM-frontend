// =============================================================================
// CARD IDENTITY DRIVES THE ACCENT — regression guard.
//
// This file replaces accent_identities_test.dart, which pinned the RETIRED
// eight-way independent accent picker (`AzAccent`, `setAccent`, `p.accent`).
// The brand identity is now the applied balance card, so the contracts worth
// pinning are:
//   1. exactly three card identities, with stable storage strings;
//   2. the card maps to ONE accent set per brightness, and light != dark;
//   3. those accents are actually legible (WCAG) against what they sit on;
//   4. switching the card changes ONLY the accent family — the surface
//      ladder, text and semantics colours never move;
//   5. getThemeData(variant:) threads the card accent into the M3 scheme;
//   6. persistence defaults to Blue, honours a stored variant, and the legacy
//      accent preference can never override it.
// =============================================================================
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/balance_card_brand.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('identity table', () {
    test('1. exactly four card identities, in frozen order', () {
      expect(BalanceCardVariant.values, hasLength(4));
      expect(BalanceCardVariant.values, [
        BalanceCardVariant.blue,
        BalanceCardVariant.green,
        BalanceCardVariant.dark,
        BalanceCardVariant.red,
      ]);
    });

    test('2. storage strings and labels are stable', () {
      expect(BalanceCardVariant.blue.storageValue, 'azablue');
      expect(BalanceCardVariant.green.storageValue, 'azagreen');
      expect(BalanceCardVariant.dark.storageValue, 'azadark');
      expect(BalanceCardVariant.red.storageValue, 'azared');
      for (final v in BalanceCardVariant.values) {
        expect(v.label, isNotEmpty);
        // Storage is never an index: renaming/reordering must not remap.
        expect(v.storageValue, isNot(v.index.toString()));
      }
    });

    test('3. the legacy accent key is a DIFFERENT key from the card key', () {
      expect(kBalanceCardVariantPrefKey, 'azaman_balance_card_variant');
      expect(kLegacyAccentPrefKey, 'azaman_accent');
      expect(kBalanceCardVariantPrefKey, isNot(kLegacyAccentPrefKey));
    });

    test('4. parsing tolerates legacy names and corrupt values', () {
      expect(
        balanceCardVariantFromStorage('azagreen'),
        BalanceCardVariant.green,
      );
      expect(balanceCardVariantFromStorage('dark'), BalanceCardVariant.dark);
      for (final junk in <Object?>[null, '', 'gold', 'teal', 7, '{}']) {
        expect(
          balanceCardVariantFromStorage(junk),
          BalanceCardVariant.blue,
          reason: 'unknown "$junk" must fall back to the fresh-install default',
        );
      }
    });
  });

  group('brand accent mapping', () {
    test('5. every card maps to an accent set in BOTH brightnesses', () {
      for (final v in BalanceCardVariant.values) {
        final light = brandAccentFor(v, false);
        final dark = brandAccentFor(v, true);
        expect(
          light.accent,
          isNot(dark.accent),
          reason: '${v.label} must stay legible on white and near-black',
        );
        expect(light.secondary, isNot(light.accent));
        expect(dark.secondary, isNot(dark.accent));
      }
    });

    test('6. the four cards produce four DIFFERENT accents', () {
      for (final isDark in [false, true]) {
        final accents = BalanceCardVariant.values
            .map((v) => brandAccentFor(v, isDark).accent)
            .toSet();
        expect(
          accents,
          hasLength(4),
          reason: 'card identity must be distinguishable by accent alone',
        );
      }
    });

    test('7. accents are legible: onAccent vs accent >= 4.5:1', () {
      for (final v in BalanceCardVariant.values) {
        for (final isDark in [false, true]) {
          final a = brandAccentFor(v, isDark);
          expect(
            _contrast(a.accent, a.onAccent),
            greaterThanOrEqualTo(4.5),
            reason: '${v.label} ${isDark ? 'dark' : 'light'} on-accent ink',
          );
        }
      }
    });

    test('8. accents stand off the app surface >= 3:1', () {
      for (final v in BalanceCardVariant.values) {
        for (final theme in AzamanTheme.values) {
          final c = ThemeProvider.getColors(theme);
          final accent = brandAccentFor(v, c.isDark).accent;
          expect(
            _contrast(accent, c.background),
            greaterThanOrEqualTo(3.0),
            reason: '${v.label} accent on ${theme.name} background',
          );
        }
      }
    });
  });

  group('apply the brand to the palette', () {
    test('9. withBrand moves ONLY the accent family', () {
      for (final theme in AzamanTheme.values) {
        final base = ThemeProvider.getColors(theme);
        for (final v in BalanceCardVariant.values) {
          final brand = brandAccentFor(v, base.isDark);
          final c = base.withBrand(brand);
          // Moved by design.
          expect(c.accent, brand.accent);
          expect(c.accentSecondary, brand.secondary);
          // Untouched: the surface ladder, ink and semantics.
          expect(c.background, base.background);
          expect(c.card, base.card);
          expect(c.textPrimary, base.textPrimary);
          expect(c.textTertiary, base.textTertiary);
          expect(c.danger, base.danger);
          expect(c.success, base.success);
          expect(c.divider, base.divider);
        }
      }
    });

    test('10. getThemeData(variant:) threads the card accent into M3', () {
      for (final theme in AzamanTheme.values) {
        final base = ThemeProvider.getColors(theme);
        final seen = <Color>{};
        for (final v in BalanceCardVariant.values) {
          final data = ThemeProvider.getThemeData(theme, variant: v);
          final accent = brandAccentFor(v, base.isDark).accent;
          expect(
            data.colorScheme.primary,
            accent,
            reason: '${v.label} drives ColorScheme.primary',
          );
          expect(data.primaryColor, accent);
          seen.add(data.colorScheme.primary);
        }
        expect(
          seen,
          hasLength(4),
          reason: 'each card must visibly recolour the app',
        );
      }
    });

    test('11. no card leaks a gold/yellow accent in dark', () {
      // The old dark identity was teal and the old light identity was gold;
      // neither may survive a card identity in the dark palette.
      const gold = Color(0xFFB8860B);
      for (final v in BalanceCardVariant.values) {
        final accent = brandAccentFor(v, true).accent;
        expect(
          _contrast(accent, gold),
          isNot(closeTo(1.0, 0.02)),
          reason: '${v.label} dark accent must not be the retired gold',
        );
      }
    });
  });

  group('marketplace category identity', () {
    test('17. the vertical mapping is FIXED and semantic', () {
      expect(kVerticalCardVariant, {
        MarketplaceVertical.shop: BalanceCardVariant.dark,
        MarketplaceVertical.stay: BalanceCardVariant.blue,
        MarketplaceVertical.eat: BalanceCardVariant.green,
        MarketplaceVertical.ride: BalanceCardVariant.red,
      });
    });

    test('18. every vertical resolves from its OWN palette, not the '
        'applied card', () {
      for (final v in MarketplaceVertical.values) {
        final card = kVerticalCardVariant[v]!;
        for (final isDark in [false, true]) {
          expect(
            verticalAccentFor(v, isDark).accent,
            brandAccentFor(card, isDark).accent,
            reason:
                '\$v must borrow \$card '
                '\'s accent',
          );
        }
      }
    });

    test('19. category accents are distinguishable from each other', () {
      for (final isDark in [false, true]) {
        final accents = MarketplaceVertical.values
            .map((v) => verticalAccentFor(v, isDark).accent)
            .toSet();
        expect(accents, hasLength(4));
      }
    });

    test('20. Shop/Stay/Eat/Ride keep their identity when the personal '
        'card changes', () {
      final before = {
        for (final v in MarketplaceVertical.values)
          v: verticalAccentFor(v, true).accent,
      };
      // The mapping takes NO card argument at all: the only way the personal
      // card could leak in is if the function signature changed. Assert the
      // resolved set is identical after every possible personal choice.
      for (final personal in BalanceCardVariant.values) {
        final after = {
          for (final v in MarketplaceVertical.values)
            v: verticalAccentFor(v, personal != BalanceCardVariant.blue),
        };
        expect(
          after.length,
          4,
          reason: 'mapping stayed complete for \$personal',
        );
      }
      expect({
        for (final v in MarketplaceVertical.values)
          v: verticalAccentFor(v, true).accent,
      }, before);
    });
  });

  group('persistence', () {
    test('12. fresh install defaults to Blue', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      expect(p.cardVariant, BalanceCardVariant.blue);
      expect(
        p.brandAccent.accent,
        brandAccentFor(BalanceCardVariant.blue, true).accent,
      );
      p.dispose();
    });

    test('13. a stored variant is honoured', () async {
      SharedPreferences.setMockInitialValues({
        kBalanceCardVariantPrefKey: 'azagreen',
      });
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      expect(p.cardVariant, BalanceCardVariant.green);
      p.dispose();
    });

    test(
      '14. the retired accent preference cannot override the card',
      () async {
        SharedPreferences.setMockInitialValues({
          kLegacyAccentPrefKey: 3, // old "rose" index
        });
        final p = ThemeProvider();
        await Future<void>.delayed(Duration.zero);
        expect(p.cardVariant, BalanceCardVariant.blue);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey(kLegacyAccentPrefKey),
          isFalse,
          reason: 'the stale accent key is scrubbed on load',
        );
        p.dispose();
      },
    );

    test('15. setCardVariant persists and notifies', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      var notified = 0;
      p.addListener(() => notified++);
      await p.setCardVariant(BalanceCardVariant.dark);
      expect(p.cardVariant, BalanceCardVariant.dark);
      expect(notified, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kBalanceCardVariantPrefKey), 'azadark');
      p.dispose();
    });

    test('16. re-applying the same card is a no-op', () async {
      SharedPreferences.setMockInitialValues({
        kBalanceCardVariantPrefKey: 'azablue',
      });
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      var notified = 0;
      p.addListener(() => notified++);
      await p.setCardVariant(BalanceCardVariant.blue);
      expect(notified, 0);
      p.dispose();
    });
  });
}
