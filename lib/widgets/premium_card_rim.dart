// =============================================================================
// AZAMAN — PREMIUM CARD RIM  (WALLET POUCH §4 — UNIFIED EDGE LANGUAGE)
//
// One shared perimeter treatment for BOTH physical cards. The Visa surface
// (PremiumCardSurface) always had a champagne-gold perimeter and glow, while
// the balance card's HolographicSurface has a much weaker bottom/right rim —
// so the balance card loses edge definition against the background. This rim
// gives both materials the SAME continuous, crisp edge:
//
//   * a continuous perimeter on all four sides (no weak bottom/right corner)
//   * a subtle metallic outer stroke — stronger top/left catch-light,
//     quieter bottom/right shading (light comes from the top-left)
//   * a fine inner hairline and a restrained shadow for real edge separation
//   * consistent corner radius and thickness cues
//   * legible in BOTH dark and light themes (the palette derives from the
//     ambient luminance rather than fixed values)
//
// It paints ONLY the edge — no body, no content, no semantics — and is
// stackable over any card material:
//
//   Stack(children: [yourMaterial, PremiumCardRim(radius: 22), yourContent])
//
// The balance card keeps its own graphite/holographic material; it is NOT
// wrapped in PremiumCardSurface — only the edge language is shared.
// =============================================================================

import 'package:flutter/material.dart';

/// A one-shot transition light, not a loop: when [sweep] transitions from 0
/// to 1 the rim's catch-light briefly strengthens along the travelling
/// edge, then settles. Driven by the host's existing transition progress —
/// the rim NEVER animates on its own clock.
class PremiumCardRim extends StatelessWidget {
  const PremiumCardRim({
    super.key,
    this.radius = 22,
    this.elevation = 0.0,
    this.sweep = 0.0,
  });

  /// The card's corner radius — must match the material beneath.
  final double radius;

  /// 0..1 how "lifted" the card reads. A lifted card earns a slightly
  /// stronger outer stroke (more light catches the edge).
  final double elevation;

  /// 0..1 one-shot transition lighting progress (e.g. the deck's emerge
  /// progress). 0 = resting rim; >0 adds a restrained brightening of the
  /// top/left catch-light that settles as the card arrives.
  final double sweep;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _PremiumCardRimPainter(
          radius: radius,
          elevation: elevation.clamp(0.0, 1.0),
          sweep: sweep.clamp(0.0, 1.0),
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PremiumCardRimPainter extends CustomPainter {
  _PremiumCardRimPainter({
    required this.radius,
    required this.elevation,
    required this.sweep,
    required this.dark,
  });

  final double radius;
  final double elevation;
  final double sweep;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // ── Palette: theme-aware, low-key metallic ──────────────────────────
    // The catch-light is a warm champagne on dark materials (matching the
    // established Visa gold) and a brighter silver-gold on light materials,
    // where a dark background would swallow a dim stroke.
    final catchLight = dark
        ? const Color(0xFFE8C97A).withValues(alpha: 0.55)
        : const Color(0xFFB99B4F).withValues(alpha: 0.75);
    final shadeSide = dark
        ? const Color(0xFF9A824C).withValues(alpha: 0.30)
        : const Color(0xFF8C7638).withValues(alpha: 0.45);
    final hairline = dark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.16)
        : const Color(0xFF000000).withValues(alpha: 0.22);

    final lift = elevation;
    final glow = sweep * 0.5; // restrained, one-shot, settles to 0

    // ── Outer metallic stroke with directional bias ─────────────────────
    // A gradient stroke: strong top-left, quiet bottom-right — light comes
    // from the top-left, so the rim reads as metal catching a lamp, not as
    // a uniform colored border.
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 + 0.5 * lift
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          catchLight.withValues(
            alpha: (catchLight.a + 0.10 * lift + 0.12 * glow).clamp(0.0, 1.0),
          ),
          shadeSide,
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.6), outer);

    // ── Inner hairline ──────────────────────────────────────────────────
    // A fine line just inside the outer stroke gives the edge a machined,
    // two-step profile (the thickness cue).
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = hairline;
    canvas.drawRRect(rrect.deflate(2.0), inner);

    // ── Edge separation shadow ──────────────────────────────────────────
    // A restrained soft shadow just outside the rim so the card separates
    // from ANY background (dark or light) without a heavy drop shadow —
    // the deck paints its own contact shadow; this is only edge crispness.
    final sep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = (dark ? const Color(0xFF000000) : const Color(0xFF6B5A2A))
          .withValues(alpha: dark ? 0.30 : 0.18);
    canvas.drawRRect(rrect.inflate(1.0), sep);
  }

  @override
  bool shouldRepaint(_PremiumCardRimPainter old) =>
      old.radius != radius ||
      old.elevation != elevation ||
      old.sweep != sweep ||
      old.dark != dark;
}
