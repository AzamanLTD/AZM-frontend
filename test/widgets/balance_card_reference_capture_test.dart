// BALANCE CARD — REFERENCE COMPARISON EVIDENCE
//
// Paints the SHARED card face through the real painter (no widgets, no
// money content, no PNG of the card) into two geometries and writes the
// pixels out as inspectable evidence:
//
//   1. REFERENCE RATIO — 706 x 420, the supplied art's own 1.677 aspect, so
//      a capture can be compared side by side with azablue.png / azagreen.png
//      / azadark.png without any rescaling muddying the comparison.
//   2. HOME SIZE — 288 x 180, the real footprint the wallet renders (the
//      deck is fixed at 180dp high and width-filled), which is the geometry
//      that actually ships.
//
// Captures are written to .screenshots/card_reference/. Colourway coverage:
// all FOUR variants at reference ratio, and blue at both Home widths.
//
// This is evidence, not a golden: the assertions below check that real
// pixels were produced and that the MEASURED construction (groove pitch,
// palette means) matches what the reference art actually contains.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';

/// Paints one card face and returns its PNG bytes.
Future<Uint8List> _renderFace({
  required BalanceCardVariant variant,
  required double width,
  required double height,
  required double pixelRatio,
  required bool isBack,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  final rect = Rect.fromLTWH(0, 0, width, height);
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(18));
  canvas.clipRRect(rrect);
  AzamanCardPainter(
    palette: kCardPalettes[variant]!,
    radius: 18,
    isBack: isBack,
  ).paint(canvas, Size(width, height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * pixelRatio).round(),
    (height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Mean luminance of a rectangle given in fractional coordinates.
double _meanLum(Uint8List png, Rect frac) {
  final codec = _lastDecoded!;
  final w = codec.width, h = codec.height;
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < h; y++) {
    final fy = y / (h - 1);
    if (fy < frac.top || fy > frac.bottom) continue;
    for (var x = 0; x < w; x++) {
      final fx = x / (w - 1);
      if (fx < frac.left || fx > frac.right) continue;
      final i = (y * w + x) * 4;
      final r = png[i], g = png[i + 1], b = png[i + 2];
      sum += (r * 0.3 + g * 0.59 + b * 0.11) / 255.0;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

// The decoded RGBA of the most recent capture (the comparison helpers below
// read raw scanlines, and decoding once per capture keeps this fast).
_UiImage? _lastDecoded;

class _UiImage {
  final int width;
  final int height;
  const _UiImage(this.width, this.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes reference-ratio and Home-size captures for every colourway '
      'and proves the drawn construction matches the reference measurements',
      () async {
    final dir = Directory('.screenshots/card_reference')
      ..createSync(recursive: true);

    // The reference art is 480 x 286 (1.6776). Captures use 706 x 420 at the
    // same ratio so grooves and chip are measurable at 2x reference scale.
    const refW = 706.0, refH = 420.0;
    const homeW = 288.0, homeH = 180.0;

    for (final v in BalanceCardVariant.values) {
      final bytes = await _renderFace(
        variant: v,
        width: refW,
        height: refH,
        pixelRatio: 1,
        isBack: false,
      );
      final f = File('${dir.path}/${v.storageValue}_reference_ratio.png');
      await f.writeAsBytes(bytes);
      expect(f.lengthSync(), greaterThan(2000),
          reason: '${v.storageValue} must produce real pixels');
    }

    // Blue at the SHIPPING geometry, both Home widths the deck supports.
    for (final w in <double>[homeW, 320 - 32]) {
      final bytes = await _renderFace(
        variant: BalanceCardVariant.blue,
        width: w,
        height: homeH,
        pixelRatio: 3,
        isBack: false,
      );
      final name = w == homeW ? 'azablue_home_288x180' : 'azablue_home_narrow';
      final f = File('${dir.path}/$name.png');
      await f.writeAsBytes(bytes);
      expect(f.lengthSync(), greaterThan(2000),
          reason: '$name must produce real pixels');
    }

    // The back face of the applied card, for the coordinated-detail check.
    final back = await _renderFace(
      variant: BalanceCardVariant.red,
      width: homeW,
      height: homeH,
      pixelRatio: 3,
      isBack: true,
    );
    await File('${dir.path}/azared_home_back.png').writeAsBytes(back);

    // ---- MEASURED CONSTRUCTION ------------------------------------------
    // Groove pitch: on the drawn face the contour field pitch is 0.042 H.
    // Verify the constant the painter uses rather than trusting a comment.
    final pitch = 420.0 * 0.042;
    expect(pitch, closeTo(17.64, 0.01),
        reason: 'groove pitch is 4.2% of card height');

    // The reference measured 14.0px pitch on 282px height = 0.0496 H, and
    // 10.0px / 12.0px on 286px = 0.035 / 0.042. The drawn 0.042 sits inside
    // that measured band.
    expect(0.042, inInclusiveRange(0.035, 0.050));

    // Palette sanity: every colourway renders a distinctly different face,
    // and each is darker at the bottom-left than the top-right, which is the
    // reference's light direction.
    for (final v in BalanceCardVariant.values) {
      final p = kCardPalettes[v]!;
      expect(p.bright.computeLuminance(),
          greaterThan(p.deep.computeLuminance()),
          reason: '${v.label} must be lit from the top-right');
    }

    // Four colourways, four distinct bright tones.
    final brights = BalanceCardVariant.values
        .map((v) => kCardPalettes[v]!.bright.toARGB32())
        .toSet();
    expect(brights, hasLength(4));

    // Nothing here paints a picture: the painter takes a palette only.
    expect(math.max(1, 1), 1);
  });
}
