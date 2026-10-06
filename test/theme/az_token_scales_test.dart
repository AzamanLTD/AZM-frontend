// =============================================================================
// TOKEN SCALE TESTS  (TASK-001)
//
// These are not "does it compile" tests. Each one pins a *design* rule that a
// careless edit could silently break:
//
//   * the ladder is strictly increasing (no two steps share a value)
//   * dark mode reads as MORE raised than light, never less
//   * a higher level is never visually weaker than the one below it
//
// The last two matter because the shadow recipes are asymmetric by design and
// nothing in the compiler stops someone from "tidying" an alpha and flattening
// the entire depth system.
// =============================================================================
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';

void main() {
  group('AzRadius', () {
    test('the ladder is strictly increasing', () {
      const steps = <double>[
        AzRadius.xs,
        AzRadius.sm,
        AzRadius.md,
        AzRadius.lg,
        AzRadius.xl,
        AzRadius.xxl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: 'step $i (${steps[i]}) must exceed step ${i - 1} (${steps[i - 1]})',
        );
      }
    });

    test('the pill step is fully round', () {
      // Larger than any real corner. If this drops, pills become lozenges.
      expect(AzRadius.pill, greaterThan(AzRadius.xxl));
    });

    test('presets carry the raw values', () {
      expect(AzRadius.brMd.topLeft.x, AzRadius.md);
      expect(AzRadius.brLg.topRight.x, AzRadius.lg);
      expect(AzRadius.brPill.topLeft.x, AzRadius.pill);
    });

    test('directional presets only round the named edge', () {
      // A sheet's top corners round; its bottom corners must stay square so it
      // sits flush against the screen edge.
      expect(AzRadius.sheetTop.topLeft.x, AzRadius.xxl);
      expect(AzRadius.sheetTop.bottomLeft.x, 0);
      expect(AzRadius.sheetTop.topRight.x, AzRadius.xxl);
      expect(AzRadius.sheetTop.bottomRight.x, 0);
    });
  });

  group('AzSpace', () {
    test('the ladder is strictly increasing', () {
      const steps = <double>[
        AzSpace.xxs,
        AzSpace.xs,
        AzSpace.sm,
        AzSpace.md,
        AzSpace.lg,
        AzSpace.xl,
        AzSpace.xxl,
        AzSpace.xxxl,
        AzSpace.huge,
        AzSpace.giant,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]),
            reason: 'gap ${steps[i]} must exceed ${steps[i - 1]}');
      }
    });

    test('every layout gap is a 4pt-based system', () {
      // `xxs` (2) is deliberately EXEMPT: az_space.dart documents it as
      // "optical nudges only (badge offset, icon baseline correction)". It is
      // a correction, not a layout gap — so it is excluded here by design,
      // and the ladder's first real step is 4.
      for (final v in <double>[
        AzSpace.xs, AzSpace.sm, AzSpace.md, AzSpace.lg,
        AzSpace.xl, AzSpace.xxl, AzSpace.xxxl, AzSpace.huge, AzSpace.giant,
      ]) {
        expect(v % 4, 0, reason: '$v is not a multiple of 4');
      }
      // And the exemption stays an exemption — it must not quietly grow to 6.
      expect(AzSpace.xxs, 2);
    });

    test('page inset matches the lg gutter', () {
      expect(AzSpace.page.left, AzSpace.lg);
      expect(AzSpace.page.right, AzSpace.lg);
    });

    test('nav clearance is tall enough to clear the floating pill', () {
      // UX-CORRECTION §4: the nav pill is the thinner icon-only pill
      // (48px tall) plus its 16px bottom gutter and breathing room — the
      // derivation documented on the token itself. A clearance smaller
      // than that means the last list item hides behind the pill.
      expect(AzSpace.navClearanceHeight, greaterThanOrEqualTo(106));
    });
  });

  group('AzElevation', () {
    /// Mean alpha across a recipe's shadows — the recipe's overall weight.
    double weight(List<BoxShadow> shadows) {
      if (shadows.isEmpty) return 0;
      final total = shadows.fold<double>(
          0, (sum, s) => sum + s.color.a);
      return total / shadows.length;
    }

    test('level 0 is flush — no shadow at all', () {
      expect(AzElevation.level0, isEmpty);
    });

    test('every level above 0 actually casts something', () {
      for (final dark in <bool>[false, true]) {
        for (var lvl = 1; lvl <= 4; lvl++) {
          List<BoxShadow> recipe;
          switch (lvl) {
            case 1: recipe = AzElevation.level1(dark); break;
            case 2: recipe = AzElevation.level2(dark); break;
            case 3: recipe = AzElevation.level3(dark); break;
            default: recipe = AzElevation.level4(dark); break;
          }
          expect(recipe, isNotEmpty, reason: 'level$lvl dark=$dark is empty');
          for (final s in recipe) {
            expect(s.color.a, greaterThan(0),
                reason: 'level$lvl dark=$dark has a fully transparent shadow');
            expect(s.blurRadius, greaterThan(0));
          }
        }
      }
    });

    test('dark mode reads as MORE raised than light, never less', () {
      // The asymmetry is the whole point: a black shadow on a black surface is
      // invisible, so dark mode must lean harder on shadow to read as lifted.
      for (var lvl = 1; lvl <= 4; lvl++) {
        List<BoxShadow> fn(bool dark) => switch (lvl) {
              1 => AzElevation.level1(dark),
              2 => AzElevation.level2(dark),
              3 => AzElevation.level3(dark),
              _ => AzElevation.level4(dark),
            };
        expect(weight(fn(true)), greaterThan(weight(fn(false))),
            reason: 'level$lvl is weaker in dark mode than light');
      }
    });

    test('a higher level is never visually weaker than the one below', () {
      for (final dark in <bool>[false, true]) {
        List<BoxShadow> fn(int lvl) => switch (lvl) {
              1 => AzElevation.level1(dark),
              2 => AzElevation.level2(dark),
              3 => AzElevation.level3(dark),
              _ => AzElevation.level4(dark),
            };
        for (var lvl = 2; lvl <= 4; lvl++) {
          expect(weight(fn(lvl)), greaterThanOrEqualTo(weight(fn(lvl - 1))),
              reason: 'level$lvl is not >= level${lvl - 1} (dark=$dark)');
        }
      }
    });

    test('every level keeps a downward offset so light reads from above', () {
      for (final dark in <bool>[false, true]) {
        for (final recipe in <List<BoxShadow>>[
          AzElevation.level1(dark),
          AzElevation.level2(dark),
          AzElevation.level3(dark),
          AzElevation.level4(dark),
        ]) {
          expect(recipe.first.offset.dy, greaterThan(0));
        }
      }
    });

    test('an explicit colour overrides the black base', () {
      const teal = Color(0xFF14B8A6);
      final custom = AzElevation.level2(false, color: teal);
      // The tint drives the hue; the recipe still controls the alphas.
      for (final s in custom) {
        expect(s.color.r, teal.r);
        expect(s.color.g, teal.g);
        expect(s.color.b, teal.b);
        expect(s.color.a, greaterThan(0));
      }
    });

    test('glow takes an intensity and stays in range', () {
      final g = AzElevation.glow(const Color(0xFFB8860B), intensity: 0.3);
      expect(g, isNotEmpty);
      for (final s in g) {
        expect(s.color.a, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
