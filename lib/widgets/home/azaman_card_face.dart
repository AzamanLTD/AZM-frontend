// =============================================================================
// AZAMAN — CODE-DRAWN BALANCE CARD FACE
//
// The card face is DRAWN, never a picture. There is no Image.asset of a card,
// no DecorationImage, no screenshot of the reference: every pixel below comes
// from gradients, vector paths and standard Flutter drawing primitives, so the
// card stays crisp at any width, in any text scale, on any pixel ratio.
//
// GEOMETRY CONTRACT (measured from the supplied reference art, 480x286):
//   • logo block: left inset 6.9% W, top 9.1% H, glyph height 10.5% H
//   • chip: x 75.0%..89.4% W, y 42.7%..63.6% H (right margin 10.6% W)
//   • gradient: bright at the TOP-RIGHT (#1A6BD4 azablue) through mid
//     (#0A499E) to deep at the BOTTOM-LEFT (#003072)
//   • contour work: concentric grooves centred behind the logo block,
//     sweeping out across the left and middle of the card
//
// The same contract drives all three variants: [AzamanCardVariantPainter] takes
// only an [AzamanCardPalette], so blue/green/dark can never drift apart
// geometrically. Horizontal metrics are fractions of the live WIDTH, vertical
// metrics fractions of the live HEIGHT, and every non-stretchable element
// (chip, glyph) is sized from HEIGHT so it can never be distorted.
//
// The frame's own footprint (180dp tall, width-filled) is untouched: this file
// fits the design INSIDE the existing geometry instead of resizing the card to
// the reference's aspect ratio.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:azaman/theme/balance_card_brand.dart';

/// The measured layout contract, in one place, so the painter and the money
/// content can never disagree about where the chip and the logo live.
/// The mark's own aspect ratio (the supplied paths' true bezier bbox:
/// 575.2 x 556.2). The card ALWAYS sizes the mark from its height through
/// this constant, so the glyph can never squash and its slot is known before
/// the vector is decoded.
const double kAzamanMarkAspect = 575.2 / 556.2;

class AzamanCardMetrics {
  const AzamanCardMetrics._();

  /// Horizontal content inset, 6.9% of the width (reference), floored so the
  /// logo never touches the edge at very narrow widths.
  static double insetX(double w) => math.max(14, w * 0.069);

  /// Vertical inset, 9.1% of the height.
  static double insetY(double h) => math.max(12, h * 0.091);

  /// Logo glyph height: 10.5% of the card height.
  static double glyphHeight(double h) => h * 0.105;

  /// Wordmark cap height implies a ~0.062 H font size (reference cap 4.4% H).
  static double wordmarkSize(double h) => h * 0.062;

  /// The chip, anchored to the right edge exactly as measured.
  static Rect chipRect(double w, double h) {
    final chipH = h * 0.209;
    // Reference aspect 51:37.6 (the EMV physical ratio); derived from height
    // so the chip never stretches with the card's width.
    final chipW = chipH * 1.357;
    final rightMargin = w * 0.106;
    final top = h * 0.427;
    return Rect.fromLTWH(w - rightMargin - chipW, top, chipW, chipH);
  }

  /// The safe area the money content may occupy: below the logo block, left of
  /// the chip column, inside the card's own inset. Nothing in the content can
  /// cover the brand mark, the chip or the contour focal point.
  static EdgeInsets contentInsets(double w, double h) {
    final chip = chipRect(w, h);
    final top = insetY(h) + glyphHeight(h) + h * 0.052;
    final right = w - chip.left + 10;
    // WHOLE PIXELS. The content column carries the card's only interactive
    // controls and its hairline type; landing its edges on device pixels
    // keeps both crisp and keeps control geometry exact. (Fractional insets
    // also made a 44dp touch target measure 43.99999999999999 under a
    // global-rect read.)
    return EdgeInsets.fromLTRB(
      insetX(w).roundToDouble(),
      top.roundToDouble(),
      right.roundToDouble(),
      (h * 0.062).roundToDouble(),
    );
  }
}

/// Paints ONE balance-card face: base gradient, tonal layering, the contour
/// grooves and the metallic chip. The logo block and the money content are
/// widgets layered on top (crisp text, real semantics).
class AzamanCardPainter extends CustomPainter {
  AzamanCardPainter({
    required this.palette,
    required this.radius,
    this.isBack = false,
  });

  final AzamanCardPalette palette;
  final double radius;

  /// The reverse side: the same construction, one tone deeper and with the
  /// contour work muted, so the back reads as the reverse of THIS card rather
  /// than a second, unrelated surface.
  final bool isBack;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.save();
    canvas.clipRRect(rrect);

    _paintBase(canvas, rect, w, h);
    _paintContours(canvas, w, h);
    // THE CHIP IS A FRONT-FACE ELEMENT ONLY. On the reverse it read as a
    // punched-out hole: the breakdown scrolls over it and there is nothing
    // for a chip to sit in. The back is the same card body, one tone deeper,
    // with no chip and no cut-out.
    if (!isBack) _paintChip(canvas, w, h);
    _paintEdgeLight(canvas, rect, rrect);

    canvas.restore();
  }

  /// 1. THE BODY. A three-stop diagonal gradient (bright top-right to deep
  /// bottom-left) plus two restrained atmosphere passes: a soft lift behind
  /// the logo and a deeper vignette in the lower-left corner. The result is
  /// the reference's "large curved surface" feel rather than a flat wash.
  void _paintBase(Canvas canvas, Rect rect, double w, double h) {
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [palette.bright, palette.mid, palette.deep],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, body);

    // Atmosphere pass 1: a broad radial lift anchored top-right-of-centre,
    // where the reference's light source sits.
    final lift = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.55, -0.75),
        radius: 1.05,
        colors: [
          Colors.white.withValues(alpha: isBack ? 0.03 : 0.05),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, lift);

    // Atmosphere pass 2: the lower-left corner settles into the deep tone.
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.85, 1.0),
        radius: 1.15,
        colors: [
          Colors.black.withValues(alpha: isBack ? 0.18 : 0.15),
          Colors.black.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  /// 2. THE CONTOUR WORK. Concentric grooves centred behind the logo block.
  /// Each ring is drawn twice: a hairline of light and a hairline of shade
  /// offset by a fraction of a pixel, which is what makes the lines read as
  /// incised curves in the surface rather than painted wire.
  void _paintContours(Canvas canvas, double w, double h) {
    final centre = Offset(w * 0.055, h * 0.045);

    // MEASURED FROM THE REFERENCE, not guessed. Groove pitch was measured on
    // all three supplied faces by finding the luminance peaks along scanlines
    // through the contour field (left 0-34% W, top 6-46% H) and taking the
    // median peak-to-peak distance: 14.0px on a 282px-high azablue, 10.0px /
    // 286px azagreen, 12.0px / 286px azadark — a median of ~0.042 H.
    //
    // The previous value (0.19 H) was 4.5x too wide, which is why the card
    // read as a handful of wide concentric rings rather than the reference's
    // fine, closely spaced flow lines. Pitch is a fraction of HEIGHT so the
    // rhythm survives every card width.
    final spacing = h * 0.042;

    // Lines are hairlines: ~1px at the reference's 282px height = 0.0035 H,
    // floored at 0.6dp so they never disappear on a 1x display.
    final strokeW = math.max(0.6, h * 0.0035);

    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..color = palette.contourLight;
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..color = palette.contourDark;

    // The field covers the left third and the top of the card, fading out
    // before it reaches the chip column: measured high-frequency energy drops
    // to near zero past ~62% W.
    final maxR = w * 0.66;
    final count = (maxR / spacing).ceil().clamp(4, 40);
    final baseLight = palette.contourLight.a * (isBack ? 0.55 : 1.0);
    final baseDark = palette.contourDark.a * (isBack ? 0.8 : 1.0);

    for (var i = 1; i <= count; i++) {
      final r = spacing * (i + 0.25);
      if (r > maxR) break;
      // Fade with radius so the grooves dissolve into the surface instead of
      // ending on a hard outer ring.
      final t = (r / maxR).clamp(0.0, 1.0);
      final fade = math.pow(1.0 - t, 1.6).toDouble();
      if (fade <= 0.02) continue;
      light.color = palette.contourLight.withValues(alpha: baseLight * fade);
      shade.color = palette.contourDark.withValues(alpha: baseDark * fade);
      // Slightly elliptical: the reference's flow lines sweep wider than they
      // are tall, following the card's curvature.
      final rRect = Rect.fromCenter(
        center: centre.translate(r * 0.10, r * 0.05),
        width: r * 2.34,
        height: r * 2.0,
      );
      canvas.drawOval(rRect, light);
      canvas.drawOval(rRect.translate(0.6, 0.9), shade);
    }
  }

  /// 3. THE CHIP. A rounded metal plate with the standard contact divisions:
  /// an inner plate line, two horizontal contact bands and the central bridge.
  /// Highlights run top-left to bottom-right, matching the card's light.
  void _paintChip(Canvas canvas, double w, double h) {
    final chip = AzamanCardMetrics.chipRect(w, h);
    final chipRRect = RRect.fromRectAndRadius(
      chip,
      Radius.circular(chip.height * 0.19),
    );

    // Plate.
    final plate = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.chipHigh, palette.chipBase, palette.chipLow],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(chip);
    canvas.drawRRect(chipRRect, plate);

    // Specular streak: the soft diagonal highlight of a brushed plate.
    canvas.save();
    canvas.clipRRect(chipRRect);
    final streak = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.46],
      ).createShader(chip);
    canvas.drawRect(chip, streak);
    canvas.restore();

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, chip.height * 0.028)
      ..color = palette.chipLine.withValues(alpha: 0.55);

    // Plate edge.
    canvas.drawRRect(chipRRect, line);

    // Inner plate: inset, itself rounded, the contact area's boundary.
    final inner = chip.deflate(chip.width * 0.115);
    final innerRRect = RRect.fromRectAndRadius(
      inner,
      Radius.circular(chip.height * 0.12),
    );
    canvas.drawRRect(innerRRect, line);

    // Contact dividers: two horizontal bands, and the central bridge between
    // them. Clipped to the plate so nothing spills past the metal edge.
    canvas.save();
    canvas.clipRRect(chipRRect);
    final divider = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, chip.height * 0.024)
      ..color = palette.chipLine.withValues(alpha: 0.42);
    final bandTop = chip.top + chip.height * 0.345;
    final bandBottom = chip.top + chip.height * 0.655;
    canvas.drawLine(
      Offset(chip.left, bandTop),
      Offset(chip.right, bandTop),
      divider,
    );
    canvas.drawLine(
      Offset(chip.left, bandBottom),
      Offset(chip.right, bandBottom),
      divider,
    );
    // The bridge: the vertical contact joining the two bands at the centre.
    final bridgeRect = Rect.fromLTRB(
      chip.left + chip.width * 0.335,
      chip.height * 0.0 + chip.top,
      chip.left + chip.width * 0.665,
      chip.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bridgeRect, Radius.circular(chip.width * 0.10)),
      divider,
    );
    canvas.restore();
  }

  /// 4. THE EDGE. A single hairline of light inside the silhouette, brightest
  /// along the top edge, which is how the reference's card edge catches its
  /// light. This is the card's own edge, not a second frame.
  void _paintEdgeLight(Canvas canvas, Rect rect, RRect rrect) {
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isBack ? 0.10 : 0.17),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), edge);
  }

  @override
  bool shouldRepaint(covariant AzamanCardPainter old) =>
      old.palette != palette || old.radius != radius || old.isBack != isBack;
}

/// The card surface: clipped painted face with the logo block pinned exactly
/// where the reference puts it, and [child] (the money content or the
/// breakdown) laid out inside the measured safe area.
class AzamanCardSurface extends StatelessWidget {
  const AzamanCardSurface({
    super.key,
    required this.variant,
    required this.radius,
    required this.child,
    this.isBack = false,
    this.childInsetOverride,
  });

  final BalanceCardVariant variant;
  final double radius;
  final Widget child;
  final bool isBack;

  /// The back face supplies its own padding (its layout is a scroll view);
  /// the front face is inset through [AzamanCardMetrics].
  final EdgeInsets? childInsetOverride;

  AzamanCardPalette get palette => kCardPalettes[variant]!;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final baseInset =
              childInsetOverride ?? AzamanCardMetrics.contentInsets(w, h);
          // THE BRAND BLOCK HAS THE TOP-LEFT CORNER ON BOTH FACES. The reverse
          // supplies its own (zero) padding for its scroll view, so its first
          // line of text used to render straight through the glyph and the
          // wordmark. Reserve the block's own band — inset + glyph height plus
          // a breath — so the breakdown begins under it.
          // Only the TOP band is reserved. An earlier version also added a
          // second horizontal inset, which narrowed the reverse's rows to
          // ~283px and made the labels wrap onto extra lines — that wrapping is
          // what pushed the section 20px past its box. The base inset already
          // clears the rounded rim; the brand band only has to clear the glyph.
          // The glyph's own height, and not a pixel more: on a 180px card every
          // extra pixel here comes straight out of the section below, and the
          // committed peek has to stay visible.
          final brandBand = AzamanCardMetrics.glyphHeight(h);
          final inset = isBack
              ? baseInset.copyWith(top: baseInset.top + brandBand)
              : baseInset;
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: AzamanCardPainter(
                  palette: palette,
                  radius: radius,
                  isBack: isBack,
                ),
              ),
              // THE BRAND BLOCK. The genuine bundled Azaman mark (the same
              // three-tier glyph as the reference art), tinted to the card's
              // ink, with the wordmark set in the app's own UI family.
              Positioned(
                left: AzamanCardMetrics.insetX(w),
                top: AzamanCardMetrics.insetY(h),
                height: AzamanCardMetrics.glyphHeight(h),
                child: AzamanCardBrandBlock(
                  glyphHeight: AzamanCardMetrics.glyphHeight(h),
                  wordmarkSize: AzamanCardMetrics.wordmarkSize(h),
                  palette: palette,
                  muted: isBack,
                ),
              ),
              Padding(padding: inset, child: child),
            ],
          );
        },
      ),
    );
  }
}

/// Glyph plus wordmark, on one optical baseline.
class AzamanCardBrandBlock extends StatelessWidget {
  const AzamanCardBrandBlock({
    super.key,
    required this.glyphHeight,
    required this.wordmarkSize,
    required this.palette,
    this.muted = false,
  });

  final double glyphHeight;
  final double wordmarkSize;
  final AzamanCardPalette palette;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final ink = muted ? palette.inkSecondary : palette.inkPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // THE MARK, AS VECTORS. Drawn from the owner's AZMSilverSVG paths
        // (plate and metallic gradients removed, viewBox cropped to the true
        // bezier bbox) so the glyph lands exactly on the logo slot and stays
        // crisp at any density — no raster asset, no filterQuality guessing.
        // srcIn tints the white paths to the card's ink while preserving the
        // three tiers' own tonal separation.
        SizedBox(
          // EXACT BOX, INDEPENDENT OF ASSET LOADING. The mark's slot is
          // computed from the glyph aspect (575.2 x 556.2), so the block has
          // its final size on the very first frame — before the SVG is
          // decoded — and the row can never reflow when the picture arrives.
          width: glyphHeight * kAzamanMarkAspect,
          height: glyphHeight,
          child: SvgPicture.asset(
            'assets/brand/azaman_mark.svg',
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
            excludeFromSemantics: true,
          ),
        ),
        SizedBox(width: glyphHeight * 0.36),
        Text(
          'Azaman',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: wordmarkSize,
            height: 1.0,
            fontWeight: FontWeight.w500,
            letterSpacing: wordmarkSize * 0.005,
            color: ink,
          ),
        ),
      ],
    );
  }
}
