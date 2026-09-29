import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/marketplace/experiences/retail/retail_experience.dart';
import 'package:azaman/marketplace/experiences/retail/retail_variant_swatches.dart';

void main() {
  group('retail shelf parallax (pure math)', () {
    test('offset is proportional to distance from the viewport centre', () {
      // viewport 400 wide: card 0 centre = 84, viewport centre = 200.
      expect(
        retailShelfParallaxOffset(index: 0, scrollX: 0, viewportWidth: 400),
        closeTo(-3.48, 1e-9),
      );
      // A card exactly at the centre has no offset.
      expect(
        retailShelfParallaxOffset(index: 0, scrollX: 0, viewportWidth: 168),
        closeTo(0.0, 1e-9),
      );
      // Off-screen cards clamp at ±6.
      expect(
        retailShelfParallaxOffset(index: 2, scrollX: 0, viewportWidth: 400),
        closeTo(6.0, 1e-9),
      );
      expect(
        retailShelfParallaxOffset(index: 0, scrollX: 178, viewportWidth: 400),
        closeTo(-6.0, 1e-9),
      );
    });

    test('scale dips for cards away from the centre and never exceeds 1', () {
      expect(
        retailShelfParallaxScale(index: 0, scrollX: 0, viewportWidth: 400),
        closeTo(0.9826, 1e-9),
      );
      expect(
        retailShelfParallaxScale(index: 0, scrollX: 0, viewportWidth: 168),
        1.0,
      );
    });
  });

  group('retail lift commit (pure rule)', () {
    test('commits at exactly 48px of damped travel', () {
      expect(retailLiftCommits(47.9), isFalse);
      expect(retailLiftCommits(48.0), isTrue);
      expect(retailLiftCommits(96.0), isTrue);
    });
  });

  group('retail variant swatches (pure detection)', () {
    test('colour groups come from the key or a hex value', () {
      expect(retailSwatchGroupIsColour('Colour', ['Red']), isTrue);
      expect(retailSwatchGroupIsColour('Color', ['#F94144']), isTrue);
      expect(retailSwatchGroupIsColour('Size', ['S', 'M', 'L']), isFalse);
      expect(retailSwatchGroupIsColour('Size', ['#F94144']), isTrue);
    });

    test('hex parsing expands 3-digit shorthand and rejects names', () {
      expect(retailSwatchColour('#abc'), const Color(0xFFAABBCC));
      expect(retailSwatchColour('F94144'), const Color(0xFFF94144));
      expect(retailSwatchColour('M'), isNull);
    });
  });
}
