// =============================================================================
// AZAMAN — PULL-REVEAL CARD DECK  (NEW-HOME §4)
//
// The horizontal balance-card rail becomes a VERTICAL two-card deck:
//   * rest      — balance card fully visible; a deliberate sliver of the Visa
//                 card peeks beneath it so the user discovers it exists.
//   * gesture   — the user PULLS the balance card upward. Not a PageView:
//                 there is tension and resistance (early drag reveals only
//                 slightly), a deliberate commit threshold, a spring snap on
//                 commit, and exactly one threshold haptic per committed
//                 pull. Release before the threshold and the deck returns.
//   * reverse   — the same resistance/snap grammar in reverse when pulled
//                 back down from the revealed state.
//   * reduced   — no spring traversal; a direct state transition that keeps
//                 the same information and gesture semantics.
//
// The geometry is testable without pumping pixels: [PullRevealPhysics] owns
// the pure drag→progress→reveal mapping and threshold decisions.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// Pure, unit-testable gesture physics.
class PullRevealPhysics {
  const PullRevealPhysics._();

  /// Drag travel (logical px) that maps to the full 0→1 reveal progress.
  static const double travelPx = 150;

  /// Fraction of the drag travel at which a release COMMITS. Intentionally
  /// past the midpoint of the resisted curve so accidental micro-drags can
  /// never open the card.
  static const double commitThreshold = 0.55;

  /// Resting sliver of the under-card visible beneath the top card (px).
  static const double restPeekPx = 20;

  /// Raw drag distance → progress fraction [0, 1].
  static double progressFor(double dragPx) {
    if (dragPx <= 0) return 0;
    return (dragPx / travelPx).clamp(0.0, 1.0);
  }

  /// Progress → reveal fraction with RESISTANCE: an ease-in square mapping,
  /// so small movement reveals only slightly and the deck pushes back.
  static double revealFor(double progress) {
    final p = progressFor(progress * travelPx);
    return p * p;
  }

  /// Whether a release at [progress] commits the reveal.
  static bool commits(double progress) => progress >= commitThreshold;
}

/// The two-card deck. [topCard] is the balance card (the hero, unchanged);
/// [bottomCard] is the Visa card revealed by the pull.
///
/// The deck reports commits through [onRevealChanged] — Home owns what
/// "revealed" means downstream (the PIN gate), so the deck stays purely a
/// gesture surface.
class PullRevealCardDeck extends ConsumerStatefulWidget {
  const PullRevealCardDeck({
    super.key,
    required this.topCard,
    required this.bottomCard,
    required this.cardHeight,
    this.onRevealChanged,
  });

  final Widget topCard;
  final Widget bottomCard;
  final double cardHeight;
  final ValueChanged<bool>? onRevealChanged;

  @override
  ConsumerState<PullRevealCardDeck> createState() => PullRevealCardDeckState();
}

/// Public on purpose: the Home deck host holds a
/// GlobalKey<PullRevealCardDeckState> so the PIN-gate flow can collapse the
/// deck programmatically when verification fails/cancels (audit §6).
class PullRevealCardDeckState extends ConsumerState<PullRevealCardDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: MotionTokens.spatial,
    lowerBound: 0,
    upperBound: 1,
    value: 0,
  );

  /// Live drag progress (raw, unrevealed-fraction) during an active gesture.
  double _dragProgress = 0;
  bool _revealed = false;
  bool _hapticArmed = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  bool get isRevealed => _revealed;

  // ── GESTURE ────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    _hapticArmed = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Pull UP (negative dy) reveals; pull DOWN (positive dy) collapses.
    final dy = -d.delta.dy;
    if (!_revealed) {
      _dragProgress = PullRevealPhysics.progressFor(
        _dragProgress * PullRevealPhysics.travelPx + dy,
      );
      _ctrl.value = PullRevealPhysics.revealFor(_dragProgress);
    } else {
      final raw = (1 - _ctrl.value).clamp(0.0, 1.0);
      final collapsed = PullRevealPhysics.progressFor(
        raw * PullRevealPhysics.travelPx + d.delta.dy,
      );
      _ctrl.value = 1 - PullRevealPhysics.revealFor(collapsed);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    final commitsNow = !_revealed && PullRevealPhysics.commits(_dragProgress);
    final collapsesNow =
        _revealed &&
        _ctrl.value <
            (1 -
                PullRevealPhysics.revealFor(PullRevealPhysics.commitThreshold));
    if (commitsNow) {
      _commit();
    } else if (collapsesNow) {
      _collapse();
    } else {
      // Below threshold: return to whichever resting state we came from.
      if (_reduceMotion) {
        _ctrl.value = _revealed ? 1.0 : 0.0;
      } else {
        _ctrl.animateWith(_springTo(_revealed ? 1.0 : 0.0));
      }
    }
    _dragProgress = 0;
  }

  SpringSimulation _springTo(double end) {
    // Deliberate card feel: moderately stiff, lightly damped so the card
    // "catches and snaps into place" without oscillating.
    const spring = SpringDescription(mass: 1, stiffness: 380, damping: 26);
    return SpringSimulation(spring, _ctrl.value, end, _ctrl.velocity * 0.4);
  }

  void _commit() {
    if (_hapticArmed) {
      // Exactly one threshold haptic per committed pull.
      AzamanHaptics.threshold();
      _hapticArmed = false;
    }
    _revealed = true;
    widget.onRevealChanged?.call(true);
    if (_reduceMotion) {
      _ctrl.value = 1.0; // direct state transition, same semantics
    } else {
      _ctrl.animateWith(_springTo(1));
    }
  }

  void _collapse() {
    if (_hapticArmed) {
      AzamanHaptics.threshold();
      _hapticArmed = false;
    }
    _revealed = false;
    widget.onRevealChanged?.call(false);
    if (_reduceMotion) {
      _ctrl.value = 0.0;
    } else {
      _ctrl.animateWith(_springTo(0));
    }
  }

  /// Programmatic collapse (e.g. the PIN gate closing).
  void collapse() {
    if (!_revealed) return;
    _revealed = false;
    widget.onRevealChanged?.call(false);
    if (_reduceMotion) {
      _ctrl.value = 0.0;
    } else {
      _ctrl.animateWith(_springTo(0));
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final t = _ctrl.value;
    const peek = PullRevealPhysics.restPeekPx;
    final h = widget.cardHeight;

    // ── DEPTH & HANDOFF (2026-10-12 refresh) ─────────────────────────────
    // Driven from the deck's EXISTING state/animation (_ctrl) — no second
    // clock competes with the established gesture physics. The balance card
    // RECEDES (small scale-down, its contact shadow and brightness fade as
    // it leaves the foreground); the Visa card ADVANCES (small scale-up to
    // full, its contact shadow grows as it becomes the next front card). No
    // tumble, no spin — depth does the work.
    final topScale = 1.0 - 0.06 * t;
    final bottomScale = 0.96 + 0.04 * t;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          child: SizedBox(
            height: h + peek,
            // §2C (2026-10-13): the peek window used a plain ClipRect,
            // so the default Visa card's visible sliver ended in a straight
            // cut — square bottom corners against the app's rounded card
            // language. The window now rounds ONLY the bottom corners (24,
            // the deck's own card-corner step), so the resting peek reads
            // as the lower edge of a real physical card. The top edge stays
            // straight: the pulled hero still exits upward through it, and
            // once revealed the Visa card's own 22-radius face sits fully
            // inside the window, untouched by the clip. Shadows are painted
            // inside the window exactly as before; nothing new is masked.
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── CRADLE STAGE ──────────────────────────────────────
                  // A curved, concave silhouette houses the lower card so
                  // the lower-card transition reads as a considered device-
                  // like stage rather than a plain rectangular block with a
                  // straight edge. The curve belongs to the SURROUNDING
                  // stage geometry only — the Visa card face is never masked
                  // or clipped.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: peek + 14,
                    child: CustomPaint(
                      painter: _CradleSilhouettePainter(
                        fill: colors.card.withValues(alpha: 0.55),
                        rim: colors.border.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  // Under-card (Visa): rises from its peeking position into
                  // the top card's slot as t → 1, growing to full scale and
                  // gaining foreground shadow.
                  Positioned(
                    top: (h - peek) * (1 - t),
                    left: 0,
                    right: 0,
                    height: h,
                    child: Transform.scale(
                      scale: bottomScale,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22 * t),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: widget.bottomCard,
                      ),
                    ),
                  ),
                  // Top card (balance): pulled upward and out of the box,
                  // receding — it scales down slightly and its foreground
                  // shadow fades, so the second card reads as taking over
                  // the foreground rather than teleporting in.
                  Positioned(
                    top: -h * t,
                    left: 0,
                    right: 0,
                    height: h,
                    child: Transform.scale(
                      scale: topScale,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: 0.22 * (1 - t),
                              ),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: widget.topCard,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── POSITION DOTS ──────────────────────────────────────────────
        // Two subtle dots communicate that there are two cards and which
        // one is in front, bound to the REAL deck state. They sit OUTSIDE
        // the drag hit area (below the gesture surface), stay clear of
        // card text, and carry semantics so the state is not colour-only.
        const SizedBox(height: AzSpace.md),
        _DeckPositionDots(revealed: _revealed),
      ],
    );
  }
}

/// Two dots, one active: the balance card (dot 0) is the resting front card;
/// the AZM Visa-concept card (dot 1) becomes the front card when the deck is
/// revealed. Subtle by design — the deck itself is the hero, the dots are a
/// quiet orientation cue.
class _DeckPositionDots extends StatelessWidget {
  const _DeckPositionDots({required this.revealed});

  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = scheme.primary;
    final inactive = scheme.outlineVariant.withValues(alpha: 0.6);
    final front = revealed ? 'AZM card' : 'balance card';
    return Semantics(
      label: 'Two cards. $front in front.',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CradleDot(
            active: !revealed,
            activeColor: active,
            inactiveColor: inactive,
          ),
          const SizedBox(width: 8),
          _CradleDot(
            active: revealed,
            activeColor: active,
            inactiveColor: inactive,
          ),
        ],
      ),
    );
  }
}

class _CradleDot extends StatelessWidget {
  const _CradleDot({
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
  });

  final bool active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? activeColor : inactiveColor,
      ),
    );
  }
}

/// The curved cradle/stage behind the lower card: rounded sides, a gentle
/// CONCAVE top edge (a shallow bowl the Visa card emerges from), one soft
/// rim-light stroke along that edge. Restrained — a surface treatment, not
/// decoration competing with the cards.
class _CradleSilhouettePainter extends CustomPainter {
  _CradleSilhouettePainter({required this.fill, required this.rim});

  final Color fill;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final hgt = size.height;

    // Bowl silhouette: bottom corners rounded (radius 22), top edge a soft
    // concave arc dipping toward the centre-bottom so the stage reads as a
    // cradle, not a rectangle.
    final path = Path()
      ..moveTo(0, hgt * 0.42)
      ..quadraticBezierTo(w * 0.5, hgt * 1.1, w, hgt * 0.42)
      ..lineTo(w, hgt - 22)
      ..quadraticBezierTo(w, hgt, w - 22, hgt)
      ..lineTo(22, hgt)
      ..quadraticBezierTo(0, hgt, 0, hgt - 22)
      ..close();

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(path, fillPaint);

    // Rim light along the concave top edge only.
    final rimPaint = Paint()
      ..color = rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(0, hgt * 0.42)
        ..quadraticBezierTo(w * 0.5, hgt * 1.1, w, hgt * 0.42),
      rimPaint,
    );
  }

  @override
  bool shouldRepaint(_CradleSilhouettePainter old) =>
      old.fill != fill || old.rim != rim;
}
