// =============================================================================
// TYPE SCALE TESTS  (TASK-002)
//
// `AzText` is the app's typography contract, so these tests assert *design
// intent*, not just that constants exist:
//
//   * every documented ladder step exists with the documented size/weight
//   * the ladder descends monotonically (a "bigger" step is never smaller)
//   * every currency figure uses TABULAR figures, so digits do not jitter as
//     a live balance counts up — the single most visible tell of an amateur
//     fintech UI
//   * `theme()` fills all 15 Material slots and carries NO colour, so the
//     caller's `.apply(bodyColor:)` is the single source of truth (TASK-004)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/theme/az_tokens.dart';

void main() {
  group('AzText ladder', () {
    /// The ladder exactly as `az_text.dart`'s header documents it.
    const documented = <String, (double, FontWeight)>{
      'hero': (AzText.sizeHero, FontWeight.w800),
      'display': (AzText.sizeDisplay, FontWeight.w800),
      'titleXl': (AzText.sizeTitleXl, FontWeight.w700),
      'titleL': (AzText.sizeTitleL, FontWeight.w700),
      'title': (AzText.sizeTitle, FontWeight.w600),
      'bodyL': (AzText.sizeBodyL, FontWeight.w500),
      'body': (AzText.sizeBody, FontWeight.w500),
      'bodyS': (AzText.sizeBodyS, FontWeight.w500),
      'label': (AzText.sizeLabel, FontWeight.w600),
      'caption': (AzText.sizeCaption, FontWeight.w600),
    };

    test('each step matches its raw size constant', () {
      final styles = <String, TextStyle>{
        'hero': AzText.hero,
        'display': AzText.display,
        'titleXl': AzText.titleXl,
        'titleL': AzText.titleL,
        'title': AzText.title,
        'bodyL': AzText.bodyL,
        'body': AzText.body,
        'bodyS': AzText.bodyS,
        'label': AzText.label,
        'caption': AzText.caption,
      };
      documented.forEach((name, spec) {
        final style = styles[name]!;
        expect(style.fontSize, spec.$1, reason: '$name size drifted');
        expect(style.fontWeight, spec.$2, reason: '$name weight drifted');
      });
    });

    test('sizes descend monotonically from hero to caption', () {
      const order = <double>[
        AzText.sizeHero,
        AzText.sizeDisplay,
        AzText.sizeTitleXl,
        AzText.sizeTitleL,
        AzText.sizeTitle,
        AzText.sizeBodyL,
        AzText.sizeBody,
        AzText.sizeBodyS,
        AzText.sizeLabel,
        AzText.sizeCaption,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(order[i], lessThan(order[i - 1]),
            reason: 'step $i (${order[i]}) is not smaller than ${order[i - 1]}');
      }
    });

    test('caption is never so small it fails legibility', () {
      // 10px is already the floor of the scale. A smaller caption is unreadable
      // on a 1.0x device, and this app targets low-end Android.
      expect(AzText.sizeCaption, greaterThanOrEqualTo(10));
    });

    test('display steps are tight-tracked, small steps are loose-tracked', () {
      // Optical correction: large type needs negative tracking or it looks
      // spaced out; small type needs positive tracking or it looks cramped.
      expect(AzText.hero.letterSpacing, lessThan(0));
      expect(AzText.display.letterSpacing, lessThan(0));
      expect(AzText.caption.letterSpacing, greaterThan(0));
      expect(AzText.eyebrow.letterSpacing, greaterThan(AzText.caption.letterSpacing!));
    });

    test('no ladder step hardcodes a colour', () {
      // Colour comes from `colors.textPrimary` at the call site. A baked-in
      // colour here would fight the theme and break dark mode.
      for (final style in <TextStyle>[
        AzText.hero, AzText.display, AzText.titleXl, AzText.titleL,
        AzText.title, AzText.bodyL, AzText.body, AzText.bodyS,
        AzText.label, AzText.caption, AzText.button, AzText.eyebrow,
      ]) {
        expect(style.color, isNull,
            reason: 'a ladder style must not carry a colour');
      }
    });
  });

  group('tabular figures', () {
    bool hasTabular(TextStyle s) =>
        s.fontFeatures?.any((f) => f.feature == 'tnum') ?? false;

    test('the tabular feature is declared and non-empty', () {
      expect(AzText.tabular, isNotEmpty);
      // `FontFeature.feature` is the OpenType tag field ('tnum'); it is NOT
      // called `tag` in the SDK.
      expect(AzText.tabular.first.feature, 'tnum');
      expect(AzText.tabular.first.value, 1);
    });

    test('every currency surface uses tabular figures', () {
      expect(hasTabular(AzText.money(Colors.black)), isTrue,
          reason: 'a live balance must not jitter digit-to-digit');
      expect(hasTabular(AzText.delta(Colors.black)), isTrue,
          reason: 'a "+0.42" delta that shifts width reads as broken');
    });

    test('money() honours a size override and keeps tabular on', () {
      final small = AzText.money(Colors.black, size: 12);
      expect(small.fontSize, 12);
      expect(hasTabular(small), isTrue);
    });

    test('money() defaults to the hero weight', () {
      expect(AzText.money(Colors.black).fontWeight, FontWeight.w800);
    });

    test('money() actually applies the colour it is given', () {
      const c = Color(0xFFB8860B);
      expect(AzText.money(c).color, c);
    });
  });

  group('AzText.theme() — Material bridge', () {
    test('fills all 15 Material text slots', () {
      final t = AzText.theme();
      final slots = <String, TextStyle?>{
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
      };
      slots.forEach((name, style) {
        expect(style, isNotNull, reason: '$name is unmapped — stock Material '
            'widgets would fall back to the M3 baseline typography');
      });
    });

    test('carries no colour, so the caller stays the source of truth', () {
      // TASK-004 does `.apply(bodyColor: c.textPrimary, displayColor: ...)`.
      // A colour baked in here would make that a silent no-op.
      final t = AzText.theme();
      for (final entry in <String, TextStyle?>{
        'displayLarge': t.displayLarge,
        'titleMedium': t.titleMedium,
        'bodyMedium': t.bodyMedium,
        'labelLarge': t.labelLarge,
      }.entries) {
        expect(entry.value?.color, isNull,
            reason: '${entry.key} must not carry a colour');
      }
    });

    test('display roles are larger than body roles', () {
      final t = AzText.theme();
      expect(t.displayLarge!.fontSize!, greaterThan(t.bodyMedium!.fontSize!));
      expect(t.titleLarge!.fontSize!, greaterThan(t.bodyMedium!.fontSize!));
      expect(t.labelLarge!.fontSize!, greaterThan(t.labelSmall!.fontSize!));
    });

    test('apply() is what injects colour, and it reaches every slot', () {
      const body = Color(0xFF111827);
      final applied = AzText.theme().apply(bodyColor: body, displayColor: body);
      expect(applied.bodyMedium?.color, body);
      expect(applied.displayLarge?.color, body);
      expect(applied.labelSmall?.color, body);
      // apply() must not disturb the sizes it was handed.
      expect(applied.bodyMedium?.fontSize, AzText.body.fontSize);
    });
  });

  group('az_tokens barrel', () {
    test('re-exports every token namespace through one import', () {
      // These references resolve ONLY if the barrel re-exports them, which is
      // exactly what this file is testing.
      expect(AzRadius.md, greaterThan(0));
      expect(AzSpace.lg, greaterThan(0));
      expect(AzElevation.level0, isEmpty);
      expect(AzText.sizeBody, greaterThan(0));
      expect(MotionTokens.standard.inMilliseconds, 220);
    });
  });
}
