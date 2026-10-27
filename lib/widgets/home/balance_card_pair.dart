// =============================================================================
// AZAMAN — BALANCE CARD PAIR (SHARED PHYSICAL CARD FRAME)
//
// Final Balance Card Redesign — visual architecture pass. The FX-status front
// (BalanceCardFx) and the icon-led breakdown back (BalanceCardBreakdown) are
// two sides of ONE premium physical card, not two independently styled cards
// that replace each other.
//
// WHAT THIS FRAME OWNS (and the faces never re-implement):
//   • ONE fixed size contract — height 165px, exactly the live Home deck's
//     card height (home_screen.dart `_cardHeight`, the deck-geometry constant
//     the cradle/pouch positioning depends on). The frame is width-filled by
//     its parent, mirroring how the Home deck lays the card out. Neither face
//     can influence this footprint: both are laid out inside tight, identical
//     constraints, so the card's layout size never changes across a flip and
//     nothing around it reflows.
//   • ONE outer material and edge language — a single HolographicSurface
//     (the app's graphite/hologram family: base + ceiling light + metallic
//     perimeter via PremiumCardRim, radius 20) that both faces live inside.
//     The back face is the SAME family, slightly more subdued (lower
//     intensity) — never a second inset card, a second border or a second
//     rim. Internal dividers separate information rows only.
//   • ONE 3D flip — the whole frame (material, rim, content) rotates
//     together; nothing stays stationary while the card turns. The back is
//     pre-rotated so its text is upright. A deliberate tap (< 8px travel,
//     the established F-024 separation) flips; a vertical drag is left for
//     the back face's inner scroll. Reduced motion lands the flip on the
//     first frame (Duration.Zero, re-checked per toggle).
//   • ONE nested-gesture guard contract — interactive affordances hosted by
//     a face (the equivalent's disclosure button,
//     back-face "return to balance" control) mark the shared flipGuard on
//     pointer-down exactly like the live card's nested affordances; the
//     frame's Listener consumes the mark on pointer-up and cedes the
//     gesture, so an affordance tap NEVER also flips the card.
//
// WIRED (superseding the old contract-seam note): this component renders
// the typed BalanceCardValuation it is given, and the live Home deck now
// mounts it through HomeBalanceCard — the production adapter
// (balanceCardValuationProvider) is the only seam numbers enter through.
// The backend valuation contract (PR #367) is still pending on the live
// API: until it ships the adapter feeds the honest interim derivation,
// and its `data.valuation` mapper activates the moment the field does.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/holographic_surface.dart';
import 'package:azaman/widgets/premium_card_rim.dart';
import 'package:azaman/widgets/home/balance_card_breakdown.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// The single geometric contract of the physical card, shared with the live
/// Home deck. The front face of the existing Home card measures 165px tall
/// (home_screen.dart `_cardHeight`) — the flip must not change it.
class BalanceCardGeometry {
  const BalanceCardGeometry._();

  static const double height = 165;
  static const double radius = 20;
}

/// The paired physical card: shared frame, one flip, two faces.
class BalanceCardPair extends StatefulWidget {
  const BalanceCardPair({
    super.key,
    required this.valuation,
    required this.colors,
    this.flipGuard,
  });

  final BalanceCardValuation valuation;
  final AzamanColors colors;

  /// The shared nested-gesture guard. When the HOST mounts card-level
  /// affordances (the Home deck's large-text overlay), it owns the guard
  /// and passes it here so both the frame's listener and the host's
  /// overlay read/write ONE mark. Null → the frame allocates its own.
  final ValueNotifier<bool>? flipGuard;

  @override
  State<BalanceCardPair> createState() => _BalanceCardPairState();
}

class _BalanceCardPairState extends State<BalanceCardPair>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flip;
  bool _isBack = false;

  /// NESTED-GESTURE GUARD — affordances hosted by a face mark this on
  /// pointer-down; the frame's Listener reads it on pointer-up and cedes
  /// the gesture (the same contract as the live card's affordances).
  /// The frame's guard: the host-supplied [BalanceCardPair.flipGuard]
  /// when the host owns card-level affordances, else a private one.
  late final ValueNotifier<bool> _flipGuard =
      widget.flipGuard ?? ValueNotifier<bool>(false);
  bool _ownsGuard = false;

  @override
  void initState() {
    super.initState();
    _ownsGuard = widget.flipGuard == null;
    _ctrl = AnimationController(vsync: this, duration: MotionTokens.spatial);
    _flip = CurvedAnimation(parent: _ctrl, curve: MotionTokens.symmetric);
  }

  @override
  void dispose() {
    if (_ownsGuard) _flipGuard.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    // A flip is a deliberate reveal of the user's own money — a selection.
    AzamanHaptics.selection();
    // Reduced motion: the flip lands on the very first frame. Read per
    // toggle so a setting that changes while the card is alive is honoured.
    _ctrl.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : MotionTokens.spatial;
    if (_isBack) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
    setState(() => _isBack = !_isBack);
  }

  @override
  Widget build(BuildContext context) {
    // The pointer contract, identical in construction to the live card:
    // a top-level raw Listener (NOT in the gesture arena, so the faces'
    // scrollables and buttons coexist) fires the flip only when pointer
    // travel is under 8px — a deliberate tap. Vertical drags belong to the
    // back face's inner scroll; nothing about a drag can flip the card.
    Offset? downAt;
    bool? downOnAffordance;
    // WORKSTREAM J3 — screen-reader/switch discoverability: the flip is
    // exposed as a REAL semantic tap action with a meaningful,
    // state-aware hint ('Show balance details' / 'Return to the
    // balance'). The semantic activation and the pointer tap both call
    // the same _toggle, so nothing about the arbitration below changes:
    // a SEMANTIC activation of the frame itself is the deliberate
    // reveal, while the nested disclosure/return controls carry their
    // own semantic taps on deeper nodes, so activating THEM never
    // reaches this action.
    return Semantics(
      key: const ValueKey('balance-pair-semantics'),
      container: true,
      button: true,
      label: _isBack
          ? 'Balance card — details breakdown'
          : 'Balance card — available balance',
      onTapHint: _isBack
          ? 'return to the balance summary'
          : 'show the balance details',
      onTap: _toggle,
      child: Listener(
        key: const ValueKey('balance-pair-flip-listener'),
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          downAt = e.position;
          // A deeper affordance Listener fires before this one, so the mark
          // is already set if the press began on a nested control.
          downOnAffordance = _flipGuard.value;
        },
        onPointerCancel: (e) {
          downAt = null;
          downOnAffordance = null;
          _flipGuard.value = false;
        },
        onPointerUp: (e) {
          final guarded = downOnAffordance ?? false;
          downOnAffordance = null;
          _flipGuard.value = false;
          if (guarded) return;
          if (downAt == null) return;
          final dist = (e.position - downAt!).distance;
          downAt = null;
          if (dist < 8) _toggle();
        },
        child: MediaQuery.withClampedTextScaling(
          // The live Home card clamps at 1.25x — the largest scale its hard
          // 165px budget accommodates at every width. Same clamp, same card.
          maxScaleFactor: 1.25,
          child: AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              final t = _flip.value;
              final angle = t * math.pi;
              final showBack = t > 0.5;

              return SizedBox(
                key: const ValueKey('balance-pair-frame'),
                height: BalanceCardGeometry.height,
                width: double.infinity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(angle),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── THE ONE MATERIAL ────────────────────────────────
                      // Both faces live inside the same HolographicSurface —
                      // the app's graphite/hologram family. The back is the
                      // same family, subdued (lower intensity): a matte
                      // reverse side, never a second card.
                      if (showBack)
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateX(math.pi),
                          child: HolographicSurface(
                            key: const ValueKey('balance-pair-back-surface'),
                            base: widget.colors.card,
                            tint: widget.colors.textSecondary,
                            intensity: 0.6,
                            sheenPeak: 0.10,
                            showSheen: false,
                            showReactiveParticles: false,
                            interactive: false,
                            borderRadius: BalanceCardGeometry.radius,
                            child: BalanceCardBreakdown(
                              valuation: widget.valuation,
                              colors: widget.colors,
                              flipGuard: _flipGuard,
                              onFlipBackRequested: _toggle,
                            ),
                          ),
                        )
                      else
                        HolographicSurface(
                          key: const ValueKey('balance-pair-front-surface'),
                          base: widget.colors.card,
                          tint: widget.colors.textSecondary,
                          showSheen: false,
                          showReactiveParticles: false,
                          interactive: false,
                          borderRadius: BalanceCardGeometry.radius,
                          child: BalanceCardFx(
                            valuation: widget.valuation,
                            colors: widget.colors,
                            flipGuard: _flipGuard,
                          ),
                        ),
                      // ── THE ONE EDGE ─────────────────────────────────────
                      // The rim is INSIDE the flip transform: the perimeter
                      // travels with the card, exactly like the live card.
                      const Positioned.fill(
                        child: PremiumCardRim(
                          radius: BalanceCardGeometry.radius,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Wraps a face-hosted interactive affordance and marks the frame's flip
/// guard on pointer-down, so tapping the affordance NEVER also flips the
/// card (the frame's Listener consumes the mark on pointer-up and cedes).
class FlipGuardMarker extends StatelessWidget {
  const FlipGuardMarker({
    super.key,
    required this.flipGuard,
    required this.child,
  });

  final ValueNotifier<bool>? flipGuard;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final guard = flipGuard;
    if (guard == null) return child;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => guard.value = true,
      child: child,
    );
  }
}
