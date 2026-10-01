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

import 'package:azaman/theme/az_motion.dart';
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
class PullRevealCardDeck extends StatefulWidget {
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
  State<PullRevealCardDeck> createState() => PullRevealCardDeckState();
}

/// Public on purpose: the Home deck host holds a
/// GlobalKey<PullRevealCardDeckState> so the PIN-gate flow can collapse the
/// deck programmatically when verification fails/cancels (audit §6).
class PullRevealCardDeckState extends State<PullRevealCardDeck>
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
          _dragProgress * PullRevealPhysics.travelPx + dy);
      _ctrl.value = PullRevealPhysics.revealFor(_dragProgress);
    } else {
      final raw = (1 - _ctrl.value).clamp(0.0, 1.0);
      final collapsed = PullRevealPhysics.progressFor(
          raw * PullRevealPhysics.travelPx + d.delta.dy);
      _ctrl.value = 1 - PullRevealPhysics.revealFor(collapsed);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    final commitsNow = !_revealed && PullRevealPhysics.commits(_dragProgress);
    final collapsesNow =
        _revealed && _ctrl.value < (1 - PullRevealPhysics.revealFor(PullRevealPhysics.commitThreshold));
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
    return SpringSimulation(spring, _ctrl.value, end,
        _ctrl.velocity * 0.4);
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
    final t = _ctrl.value;
    const peek = PullRevealPhysics.restPeekPx;
    final h = widget.cardHeight;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: SizedBox(
        height: h + peek,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Under-card (Visa): rises from its peeking position into the
              // top card's slot as t → 1.
              Positioned(
                top: (h - peek) * (1 - t),
                left: 0,
                right: 0,
                height: h,
                child: widget.bottomCard,
              ),
              // Top card (balance): pulled upward and out of the box.
              Positioned(
                top: -h * t,
                left: 0,
                right: 0,
                height: h,
                child: widget.topCard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
