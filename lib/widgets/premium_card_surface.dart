// =============================================================================
// AZMAN — PREMIUM PHYSICAL-CARD SURFACE  (UX-CORRECTION §3)
//
// The visual grammar of the P2P _CashBalanceCard (lib/screens/p2p/
// p2p_marketplace_screen.dart), extracted NARROWLY so the AZM Visa card
// can wear the same premium physical-bank-card treatment WITHOUT
// importing P2P semantics. This widget paints ONLY the surface:
//
//   * carbon/black card body (fixed brand palette, deliberately NOT the
//     switchable theme accent — a physical card does not change colour
//     when the phone switches to dark mode)
//   * rich diagonal gradient with a controlled gold blend
//   * premium gold rim
//   * controlled gold accent glow/shadow
//   * subtle ring texture (top-right)
//   * restrained slow sheen sweep
//
// It renders NO content, NO text, NO semantics: the caller stacks its own
// children on top. The P2P card itself is untouched (it keeps its own
// in-place treatment and its business logic).
// =============================================================================

import 'package:flutter/widgets.dart';

/// Permanent brand palette (identical values to the P2P card's).
abstract final class PremiumCardPalette {
  static const Color cardAccent = Color(0xFFD4AF37); // gold — not theme accent
  static const Color gradTopBase = Color(0xFF0E1116);
  static const Color gradBottom = Color(0xFF05070A);
}

/// The premium physical-card surface. Stack [child] on top:
///
///   Stack(children: [PremiumCardSurface(radius: 22), ...yourCardContent])
///
/// or use [PremiumCardFrame] which does the stacking for you.
class PremiumCardSurface extends StatelessWidget {
  const PremiumCardSurface({super.key, this.radius = 22});

  final double radius;

  @override
  Widget build(BuildContext context) {
    const gold = PremiumCardPalette.cardAccent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          // Carbon-to-black gradient body with a controlled gold blend.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                        gold.withValues(alpha: 0.16),
                        PremiumCardPalette.gradTopBase),
                    PremiumCardPalette.gradBottom,
                  ],
                ),
                border: Border.all(color: gold.withValues(alpha: 0.22), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: gold.withValues(alpha: 0.14),
                    blurRadius: 28,
                    spreadRadius: -6,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
            ),
          ),
          // Faint decorative card texture — soft gold ring, top-right.
          Positioned(
            right: -40,
            top: -50,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: gold.withValues(alpha: 0.10), width: 22),
                ),
              ),
            ),
          ),
          // Restrained slow diagonal glass sheen sweep.
          Positioned.fill(
            child: IgnorePointer(
              child: _PremiumCardSheen(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.05)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience wrapper: [PremiumCardSurface] painted behind [child].
class PremiumCardFrame extends StatelessWidget {
  const PremiumCardFrame({
    super.key,
    this.radius = 22,
    required this.child,
  });

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: PremiumCardSurface(radius: radius)),
        child,
      ],
    );
  }
}

/// The same slow diagonal sheen sweep the P2P card uses, extracted with
/// its exact grammar (3600ms loop, band 0.30w wide, rotate -0.4, eased
/// left-to-right sweep). The platform's disableAnimations setting parks
/// the band off-card — reduced-motion users see the plain carbon body.
class _PremiumCardSheen extends StatefulWidget {
  const _PremiumCardSheen({required this.color});

  final Color color;

  @override
  State<_PremiumCardSheen> createState() => _PremiumCardSheenState();
}

class _PremiumCardSheenState extends State<_PremiumCardSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w <= 0 || !w.isFinite || disableAnimations) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              // Slow diagonal band sweeps left-to-right and loops.
              final t = Curves.easeInOutSine.transform(_ctrl.value);
              final dx = -w * 0.7 + t * w * 1.9;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Transform.rotate(
                  angle: -0.4,
                  child: Container(
                    width: w * 0.30,
                    height: w * 2.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          widget.color.withValues(alpha: 0.0),
                          widget.color,
                          widget.color.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
