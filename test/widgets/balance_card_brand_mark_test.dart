// =============================================================================
// THE CARD MARK IS A VECTOR
//
// The owner supplied the AZAMAN three-tier mark as an SVG (1024x1024 artboard,
// dark plate, metallic gradients). These tests pin the transformation that
// makes it usable on the card:
//
//   1. THE ASSET. The bundled asset is the three source paths with the plate
//      and gradients gone and a viewBox cropped to the glyph's true bezier
//      bbox — so the mark FILLS its slot instead of sitting in 1024-square
//      padding. Re-adding a plate or a gradient reference fails here.
//   2. THE SLOT. On the card the mark occupies exactly the measured logo box:
//      height = AzamanCardMetrics.glyphHeight, left/top = the reference
//      insets, aspect = the glyph's own 1.0342. No stretching, no offsets.
//   3. VECTORS, NOT PIXELS. The brand block draws an SvgPicture. If anyone
//      swaps the mark back to a raster Image.asset, that fails here too.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';
import 'package:azaman/widgets/home/balance_card_pair.dart'
    show BalanceCardGeometry;

const String _assetPath = 'assets/brand/azaman_mark.svg';

/// The glyph's own aspect from the supplied paths (575.2 x 556.2).
const double _glyphAspect = 575.2 / 556.2;

void main() {
  group('the bundled mark asset', () {
    test(
      'is the three source paths, cropped, with no plate and no gradients',
      () {
        final svg = File(_assetPath).readAsStringSync();

        // The three tiers survive, in order, as real vectors.
        expect(
          '<path'.allMatches(svg).length,
          3,
          reason: 'crown, middle and foundation are the whole mark',
        );

        // The dark 1024 artboard plate must NOT be shipped: it would paint a
        // black square behind the glyph on the card.
        expect(
          svg.contains('<rect'),
          isFalse,
          reason: 'the source plate is not part of the mark',
        );
        expect(svg.contains('#1E1E1E'), isFalse);

        // No gradient references: the card tints a flat white mark to its own
        // ink, and a surviving url(#paint…) would silently override that.
        expect(svg.contains('url(#'), isFalse);
        expect(svg.contains('<linearGradient'), isFalse);

        // Cropped to the glyph, not left in 1024-square padding.
        expect(
          svg.contains('viewBox="224.4 214 575.2 556.2"'),
          isTrue,
          reason: 'the viewBox is the glyph bezier bbox, so it fills the slot',
        );
        expect(svg.contains('0 0 1024 1024'), isFalse);
      },
    );

    test('every tier is white so srcIn can tint it to the card ink', () {
      final svg = File(_assetPath).readAsStringSync();
      expect('fill="#FFFFFF"'.allMatches(svg).length, 3);
      // Subtle tonal separation between the tiers is preserved as opacity.
      expect(svg.contains('fill-opacity="1.0"'), isTrue);
      expect(svg.contains('fill-opacity="0.96"'), isTrue);
      expect(svg.contains('fill-opacity="0.90"'), isTrue);
    });
  });

  group('the mark on the card face', () {
    testWidgets('is drawn as vectors, never as a raster image', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: AzamanCardBrandBlockFixture())),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AzamanCardBrandBlock),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
        reason: 'the mark is a vector at every size',
      );
      expect(
        find.descendant(
          of: find.byType(AzamanCardBrandBlock),
          matching: find.byType(Image),
        ),
        findsNothing,
        reason: 'a raster mark would soften at 3x density',
      );
    });

    testWidgets('lands exactly on the measured logo slot', (tester) async {
      const double cardWidth = 358;
      const double cardHeight = 180;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: AzamanCardSurface(
                  variant: BalanceCardVariant.blue,
                  radius: 20,
                  child: SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final mark = find.descendant(
        of: find.byType(AzamanCardBrandBlock),
        matching: find.byType(SvgPicture),
      );
      expect(mark, findsOneWidget);
      final rect = tester.getRect(mark);

      // Height is the metric's glyph height, exactly.
      expect(
        rect.height,
        closeTo(AzamanCardMetrics.glyphHeight(cardHeight), 0.01),
      );

      // The glyph's own aspect: the width follows the height, never squashed.
      expect(rect.width / rect.height, closeTo(_glyphAspect, 0.02));

      // Anchored on the reference insets, measured FROM THE CARD'S OWN EDGE
      // (getRect is global, so the card's origin is subtracted).
      final card = tester.getRect(find.byType(AzamanCardSurface));
      final block = tester.getRect(find.byType(AzamanCardBrandBlock));
      expect(
        block.left - card.left,
        closeTo(AzamanCardMetrics.insetX(cardWidth), 0.01),
      );
      expect(
        block.top - card.top,
        closeTo(AzamanCardMetrics.insetY(cardHeight), 0.01),
      );
      expect(
        rect.top,
        closeTo(block.top, 0.51),
        reason: 'the glyph sits on the block, centered, never offset',
      );
      expect(
        rect.left - card.left,
        closeTo(AzamanCardMetrics.insetX(cardWidth), 0.01),
        reason: 'the glyph starts exactly on the reference left inset',
      );
    });

    testWidgets('is tinted to each variant\'s own ink', (tester) async {
      for (final variant in BalanceCardVariant.values) {
        final palette = kCardPalettes[variant]!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: AzamanCardBrandBlock(
                  glyphHeight: 18.9,
                  wordmarkSize: 12,
                  palette: palette,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        final filter = svg.colorFilter;
        expect(filter, isNotNull, reason: '${variant.name}: tinted, not raw');
        // srcIn with the variant's ink: the white paths become the card's
        // own foreground colour without touching their anti-aliased edges.
        expect(
          filter,
          ColorFilter.mode(palette.inkPrimary, BlendMode.srcIn),
          reason: '${variant.name}: the mark takes the card ink',
        );
      }
    });
  });
}

/// A bare brand block at a fixed size, for the "vectors only" assertion.
class AzamanCardBrandBlockFixture extends StatelessWidget {
  const AzamanCardBrandBlockFixture({super.key});

  @override
  Widget build(BuildContext context) {
    return AzamanCardBrandBlock(
      glyphHeight: AzamanCardMetrics.glyphHeight(BalanceCardGeometry.height),
      wordmarkSize: AzamanCardMetrics.wordmarkSize(BalanceCardGeometry.height),
      palette: kCardPalettes[BalanceCardVariant.blue]!,
    );
  }
}
