// PUBLIC TOUR — SLIDE ARTWORK.
//
// The first three screens a new person ever sees. The previous art was a
// placeholder glyph per slide (a rounded rectangle standing in for a card, a
// grid standing in for a marketplace), which is why the tour read as a
// developer wireframe.
//
// These compositions are built from the product's own material:
//   • Wallet      — the REAL code-drawn balance card (BalanceCardFx), the same
//                   widget Home uses, so the first slide is literally the
//                   product rather than a drawing of it.
//   • Marketplace — category tiles tinted from the SAME shared palettes the
//                   marketplace binds to (Shop dark, Stay blue, Eat green,
//                   Ride red), with motifs drawn as vectors.
//   • Community   — chat bubbles and a Susu circle, drawn, not screenshotted.
//
// What is NOT here: merchant names, ratings, prices, live availability,
// invented balances shown as real, or any claim of a completed transfer. The
// wallet card carries an "Example" badge for exactly that reason.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';

/// What a slide shows, as opposed to what it says.
enum IntroArt { wallet, marketplace, community }

/// Clearly-labelled example figures for the wallet slide.
///
/// These are NOT anyone's balance. The badge under the card says "Example",
/// and the copy explains that GHS is the native figure while the USDC line is
/// a conversion. The rate is fixed so the slide cannot drift with live FX.
BalanceCardValuation introExampleValuation() => BalanceCardValuation(
  nativeGhsAvailable: 1250,
  availableUsdc: 96,
  balanceConfirmed: true,
  escrowLocked: 40,
  vaultLocked: 60,
  susuCommitted: 30,
  rate: FxRateView(
    ghsPerUsdc: 12.03,
    kind: FxRateKind.saved,
    sourceLabel: 'example rate',
    observedAt: DateTime.utc(2026, 10, 22, 9, 30),
  ),
).compute();

class IntroSlideArt extends StatelessWidget {
  const IntroSlideArt({super.key, required this.art, required this.colors});

  final IntroArt art;
  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    switch (art) {
      case IntroArt.wallet:
        return _WalletArt(colors: colors);
      case IntroArt.marketplace:
        return _MarketplaceArt(colors: colors);
      case IntroArt.community:
        return _CommunityArt(colors: colors);
    }
  }
}

// ── Slide 1: the wallet ────────────────────────────────────────────────────

class _WalletArt extends StatelessWidget {
  const _WalletArt({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) {
    final palette = kCardPalettes[BalanceCardVariant.blue]!;
    // The badge is text, so the art's height is text-scale dependent. A fixed
    // box clipped at 1.6x on a 320dp phone.
    final badgeHeight =
        MediaQuery.textScalerOf(context).scale(10.5) * 2 + 8 + 8;
    return SizedBox(
      height: 180 + 12 + badgeHeight + 10,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = math.min(constraints.maxWidth, 300.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              // A pool of the card's own light, so the card sits in the scene
              // instead of being pasted onto it.
              Positioned(
                top: 6,
                child: Container(
                  width: cardWidth * 0.92,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(90),
                    gradient: RadialGradient(
                      colors: [
                        palette.bright.withValues(alpha: 0.26),
                        palette.deep.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // The ghost plate: depth without a second card, tilted behind
              // the real one at low opacity.
              Transform.translate(
                offset: const Offset(0, 14),
                child: Transform.rotate(
                  angle: -0.05,
                  child: Container(
                    width: cardWidth * 0.94,
                    height: 176,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          palette.mid.withValues(alpha: 0.55),
                          palette.deep.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: cardWidth,
                    height: 180,
                    child: BalanceCardFx(
                      valuation: introExampleValuation(),
                      colors: colors,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ExampleBadge(colors: colors),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExampleBadge extends StatelessWidget {
  const _ExampleBadge({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: colors.softSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: colors.divider),
    ),
    child: Text(
      'Example balance',
      style: TextStyle(
        color: colors.textTertiary,
        fontSize: 10.5,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ── Slide 2: the marketplace ───────────────────────────────────────────────

class _MarketplaceArt extends StatelessWidget {
  const _MarketplaceArt({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 236,
    child: CustomPaint(
      painter: _MarketplacePainter(colors: colors),
      size: Size.infinite,
    ),
  );
}

class _MarketplacePainter extends CustomPainter {
  _MarketplacePainter({required this.colors});

  final AzamanColors colors;

  /// The SAME identities the marketplace binds to. Fixed and semantic: the
  /// tour may not re-tint them.
  static const List<(BalanceCardVariant, _CategoryGlyph)> _tiles =
      <(BalanceCardVariant, _CategoryGlyph)>[
        (BalanceCardVariant.dark, _CategoryGlyph.shop),
        (BalanceCardVariant.blue, _CategoryGlyph.stay),
        (BalanceCardVariant.green, _CategoryGlyph.eat),
        (BalanceCardVariant.red, _CategoryGlyph.ride),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 12.0;
    const pad = 2.0;
    final tileW = (size.width - pad * 2 - gap) / 2;
    final tileH = (size.height - pad * 2 - gap) / 2;

    for (var i = 0; i < _tiles.length; i++) {
      final (variant, glyph) = _tiles[i];
      final palette = kCardPalettes[variant]!;
      final col = i % 2;
      final row = i ~/ 2;
      final rect = Rect.fromLTWH(
        pad + col * (tileW + gap),
        pad + row * (tileH + gap),
        tileW,
        tileH,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));

      // Soft contact shadow, then the tile's own vertical gradient.
      canvas.drawRRect(
        rrect.shift(const Offset(0, 5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.bright, palette.mid, palette.deep],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      );
      // A single hairline of the tile's own highlight keeps the edges crisp
      // against a dark ground.
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.contourLight.withValues(alpha: 0.35),
      );

      _drawGlyph(canvas, glyph, rect, palette);
    }
  }

  void _drawGlyph(
    Canvas canvas,
    _CategoryGlyph glyph,
    Rect tile,
    AzamanCardPalette palette,
  ) {
    final ink = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final s = math.min(tile.width, tile.height) * 0.30;
    final c = tile.center;
    canvas.save();
    canvas.translate(c.dx, c.dy);

    switch (glyph) {
      case _CategoryGlyph.shop:
        // Bag: tapered body + handle.
        final body = Path()
          ..moveTo(-s * 0.62, -s * 0.10)
          ..lineTo(s * 0.62, -s * 0.10)
          ..lineTo(s * 0.50, s * 0.72)
          ..lineTo(-s * 0.50, s * 0.72)
          ..close();
        canvas.drawPath(body, ink);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(0, -s * 0.10), radius: s * 0.34),
          math.pi,
          math.pi,
          false,
          ink,
        );
      case _CategoryGlyph.stay:
        // Bed: mattress, headboard, pillow.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(0, s * 0.22),
              width: s * 1.34,
              height: s * 0.46,
            ),
            Radius.circular(s * 0.10),
          ),
          ink,
        );
        canvas.drawLine(
          Offset(-s * 0.60, s * 0.22),
          Offset(-s * 0.60, -s * 0.52),
          ink,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(-s * 0.24, s * 0.02),
              width: s * 0.46,
              height: s * 0.26,
            ),
            Radius.circular(s * 0.08),
          ),
          ink,
        );
      case _CategoryGlyph.eat:
        // Plate + fork.
        canvas.drawCircle(Offset(s * 0.22, 0), s * 0.52, ink);
        canvas.drawLine(
          Offset(-s * 0.62, -s * 0.58),
          Offset(-s * 0.62, s * 0.58),
          ink,
        );
        for (var i = -1; i <= 1; i++) {
          canvas.drawLine(
            Offset(-s * 0.62, -s * 0.58),
            Offset(-s * 0.62 + i * s * 0.16, -s * 0.30),
            ink,
          );
        }
      case _CategoryGlyph.ride:
        // Car: body, roof, two wheels.
        final body = Path()
          ..moveTo(-s * 0.72, s * 0.18)
          ..lineTo(-s * 0.50, -s * 0.16)
          ..lineTo(-s * 0.12, -s * 0.40)
          ..lineTo(s * 0.28, -s * 0.34)
          ..lineTo(s * 0.62, -s * 0.04)
          ..lineTo(s * 0.72, s * 0.18)
          ..close();
        canvas.drawPath(body, ink);
        canvas.drawCircle(Offset(-s * 0.36, s * 0.30), s * 0.16, ink);
        canvas.drawCircle(Offset(s * 0.36, s * 0.30), s * 0.16, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarketplacePainter oldDelegate) =>
      oldDelegate.colors != colors;
}

enum _CategoryGlyph { shop, stay, eat, ride }

// ── Slide 3: people and community ──────────────────────────────────────────

class _CommunityArt extends StatelessWidget {
  const _CommunityArt({required this.colors});

  final AzamanColors colors;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 236,
    child: CustomPaint(
      painter: _CommunityPainter(colors: colors),
      size: Size.infinite,
    ),
  );
}

/// Chat bubbles and a Susu circle.
///
/// The bubbles carry typed-line marks, not sentences about money: a tour must
/// not imply a transfer has happened. The Susu ring shows members, not amounts.
class _CommunityPainter extends CustomPainter {
  _CommunityPainter({required this.colors});

  final AzamanColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = colors.accent;
    final w = size.width;

    // Susu circle: six member dots on an arc, three of them joined by the
    // accent, which reads as "a group keeping a rhythm" without claiming a
    // balance.
    final ringCenter = Offset(w * 0.73, size.height * 0.30);
    final ringR = math.min(w, size.height) * 0.20;
    final dot = math.max(3.4, ringR * 0.13);
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + (i / 6) * math.pi * 2;
      final p = Offset(
        ringCenter.dx + math.cos(a) * ringR,
        ringCenter.dy + math.sin(a) * ringR,
      );
      final active = i < 3;
      canvas.drawCircle(
        p,
        dot,
        Paint()
          ..color = active
              ? accent
              : colors.textTertiary.withValues(alpha: 0.45),
      );
    }
    canvas.drawArc(
      Rect.fromCircle(center: ringCenter, radius: ringR),
      -math.pi / 2,
      math.pi * (2 / 6) * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.55),
    );

    // Three bubbles, alternating sides, each with its own radius and a tail
    // that points at the speaker.
    _bubble(
      canvas,
      rect: Rect.fromLTWH(w * 0.04, size.height * 0.14, w * 0.52, 54),
      fill: colors.softSurface,
      stroke: colors.divider,
      tailLeft: true,
      lines: 2,
      lineColor: colors.textTertiary,
    );
    _bubble(
      canvas,
      rect: Rect.fromLTWH(w * 0.26, size.height * 0.36, w * 0.56, 62),
      fill: accent.withValues(alpha: 0.16),
      stroke: accent.withValues(alpha: 0.34),
      tailLeft: false,
      lines: 2,
      lineColor: colors.textSecondary,
    );
    _bubble(
      canvas,
      rect: Rect.fromLTWH(w * 0.08, size.height * 0.60, w * 0.48, 54),
      fill: colors.softSurface,
      stroke: colors.divider,
      tailLeft: true,
      lines: 1,
      lineColor: colors.textTertiary,
    );
  }

  void _bubble(
    Canvas canvas, {
    required Rect rect,
    required Color fill,
    required Color stroke,
    required bool tailLeft,
    required int lines,
    required Color lineColor,
  }) {
    final radius = Radius.circular(rect.height * 0.42);
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: radius,
      topRight: radius,
      bottomLeft: tailLeft ? const Radius.circular(6) : radius,
      bottomRight: tailLeft ? radius : const Radius.circular(6),
    );
    canvas.drawRRect(
      rrect.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke,
    );

    // Type marks rather than invented sentences.
    final lineH = math.max(4.0, rect.height * 0.11);
    for (var i = 0; i < lines; i++) {
      final widthFactor = i == 0 ? 0.62 : 0.40;
      final y = rect.top + rect.height * (0.34 + i * 0.26);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + rect.width * 0.16,
            y,
            rect.width * widthFactor,
            lineH,
          ),
          Radius.circular(lineH / 2),
        ),
        Paint()..color = lineColor.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(_CommunityPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
