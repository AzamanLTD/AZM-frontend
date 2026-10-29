// =============================================================================
// AZAMAN — BALANCE CARD PAIR (SHARED PHYSICAL CARD FRAME)
//
// Final Balance Card Redesign — visual architecture pass. The FX-status front
// (BalanceCardFx) and the icon-led breakdown back (BalanceCardBreakdown) are
// two sides of ONE premium physical card, not two independently styled cards
// that replace each other.
//
// WHAT THIS FRAME OWNS (and the faces never re-implement):
//   • ONE fixed size contract — height 180px, the ORIGINAL deck geometry
//     (d63a4d4; the 2026-10-12 refresh had briefly reduced it to 165, which
//     the 2026-10-27 UX pass restored — the balance card is the product's
//     primary money surface and the founder wants the larger presentation:
//     the GHS headline, the USDC-equivalent line and the FX status row each
//     get a fixed reserved region inside the frame). The frame is width-filled
//     by its parent, mirroring how the Home deck lays the card out (its
//     `_cardHeight` mirrors BalanceCardGeometry.height). Neither face can
//     influence this footprint: both are laid out inside tight, identical
//     constraints, so the card's layout size never changes across a flip and
//     nothing around it reflows.
//   • ONE PAINTED CARD, ONE EDGE. Both faces are drawn by the SAME card code
//     (AzamanCardSurface/AzamanCardPainter in azaman_card_face.dart): one
//     silhouette, one gradient construction, one contour rhythm, one chip, one
//     hairline edge. The back face is the same card one tone deeper with the
//     contour work muted: never a second inset card, border or rim. Internal
//     dividers separate information rows only.
//   • ONE BRAND IDENTITY. The applied BalanceCardVariant paints BOTH faces, so
//     the reverse always belongs to the card on the front.
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:azaman/models/balance_card_valuation.dart';
import 'package:azaman/providers/theme_provider.dart' show AzamanColors;
import 'package:azaman/theme/balance_card_brand.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/widgets/home/azaman_card_face.dart';
import 'package:azaman/widgets/home/balance_card_breakdown.dart';
import 'package:azaman/widgets/home/balance_card_fx.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// The single geometric contract of the physical card, shared with the live
/// Home deck (home_screen.dart `_cardHeight`). 180px is the ORIGINAL deck
/// geometry (d63a4d4; restored by the 2026-10-27 UX pass after the brief
/// 165px reduction) — the flip must not change it, and neither may any data
/// state: the frame's footprint is identical whether the balance, the rate
/// or both are loading, unavailable or populated.
/// The press-and-hold threshold for opening the wallet card selector. The
/// platform's own long-press constant, so the card feels like the rest of the
/// OS rather than an invented timing.
const Duration kCardHoldDuration = Duration(milliseconds: 480);

class BalanceCardGeometry {
  const BalanceCardGeometry._();

  static const double height = 180;
  static const double radius = 20;
}

/// The paired physical card: shared frame, one flip, two faces.
/// The on-card colour ladder for a variant: the theme's own semantics with
/// every ink value replaced by the applied card's tones, so the faces stay
/// palette-agnostic and read a normal [AzamanColors].
///
/// Public because the public tour draws the same card (the wallet slide's
/// hero) and must obey the same ladder as Home — otherwise the tour's card
/// would be a look-alike with off-palette ink.
AzamanColors balanceCardInk(BalanceCardVariant variant, AzamanColors colors) {
  final p = kCardPalettes[variant]!;
  return colors.copyWith(
    card: p.mid,
    textPrimary: p.inkPrimary,
    textSecondary: p.inkSecondary,
    textTertiary: p.inkTertiary,
    divider: p.inkDivider,
    accent: p.inkAccent,
    accentSecondary: p.inkAccent,
    accentSurface: p.inkAccent.withValues(alpha: 0.16),
    glow: p.inkAccent,
    border: p.inkDivider,
  );
}

class BalanceCardPair extends StatefulWidget {
  const BalanceCardPair({
    super.key,
    required this.valuation,
    required this.colors,
    this.variant = BalanceCardVariant.blue,
    this.flipGuard,
    this.onCardLongPress,
  });

  final BalanceCardValuation valuation;
  final AzamanColors colors;

  /// The applied balance-card identity. Both faces are painted from this one
  /// variant, so the reverse always belongs to the card the user chose.
  final BalanceCardVariant variant;

  /// A deliberate press-and-hold on the card asks the host to open the wallet
  /// card selector. Null keeps the card long-press-free (tests, sheets).
  final VoidCallback? onCardLongPress;

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

  /// PRESS-AND-HOLD. A timer armed on pointer-down and disarmed on travel or
  /// release. When it fires the selector opens and the SAME gesture is
  /// consumed: the release must not also flip the card underneath.
  Timer? _holdTimer;
  bool _holdFired = false;

  @override
  void initState() {
    super.initState();
    _ownsGuard = widget.flipGuard == null;
    _ctrl = AnimationController(vsync: this, duration: MotionTokens.spatial);
    _flip = CurvedAnimation(parent: _ctrl, curve: MotionTokens.symmetric);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
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

  /// The colour ladder the faces draw with. Kept as a field accessor so the
  /// faces below read exactly as before.
  AzamanColors get _ink => balanceCardInk(widget.variant, widget.colors);

  /// Fired by the hold timer: the card lifts away from the wallet and the
  /// host opens the selector. The gesture is consumed so the release cannot
  /// flip the card.
  void _onHold() {
    _holdTimer = null;
    if (!mounted) return;
    _holdFired = true;
    AzamanHaptics.threshold();
    widget.onCardLongPress?.call();
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
          _holdFired = false;
          _holdTimer?.cancel();
          if (widget.onCardLongPress != null && !(downOnAffordance ?? false)) {
            _holdTimer = Timer(kCardHoldDuration, _onHold);
          }
        },
        onPointerMove: (e) {
          // Any real travel is a drag (the back face's scroll, a sheet) and
          // never a hold; disarming on the way keeps the two gestures
          // mutually exclusive without a competing recogniser.
          if (downAt != null && (e.position - downAt!).distance >= 8) {
            _holdTimer?.cancel();
            _holdTimer = null;
          }
        },
        onPointerCancel: (e) {
          _holdTimer?.cancel();
          _holdTimer = null;
          downAt = null;
          downOnAffordance = null;
          _flipGuard.value = false;
        },
        onPointerUp: (e) {
          _holdTimer?.cancel();
          _holdTimer = null;
          final guarded = downOnAffordance ?? false;
          final held = _holdFired;
          downOnAffordance = null;
          _flipGuard.value = false;
          if (guarded || held) {
            // The hold already did its job: the release is consumed, it must
            // NOT flip the card as well.
            downAt = null;
            _holdFired = false;
            return;
          }
          if (downAt == null) return;
          final dist = (e.position - downAt!).distance;
          downAt = null;
          if (dist < 8) _toggle();
        },
        child: MediaQuery.withClampedTextScaling(
          // The live Home card clamps at 1.25x — the largest scale its hard
          // 180px budget accommodates at every width. Same clamp, same card.
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
                      // ── THE ONE PAINTED CARD ────────────────────────
                      // Both faces are drawn from the SAME code: one painter,
                      // one geometry contract, one palette family. The reverse
                      // is the same card one tone deeper, never a second card
                      // and never a second rim.
                      if (showBack)
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateX(math.pi),
                          child: AzamanCardSurface(
                            key: const ValueKey('balance-pair-back-surface'),
                            variant: widget.variant,
                            isBack: true,
                            radius: BalanceCardGeometry.radius,
                            childInsetOverride: EdgeInsets.zero,
                            child: BalanceCardBreakdown(
                              valuation: widget.valuation,
                              colors: _ink,
                              flipGuard: _flipGuard,
                              onFlipBackRequested: _toggle,
                            ),
                          ),
                        )
                      else
                        AzamanCardSurface(
                          key: const ValueKey('balance-pair-front-surface'),
                          variant: widget.variant,
                          radius: BalanceCardGeometry.radius,
                          child: BalanceCardFx(
                            valuation: widget.valuation,
                            colors: _ink,
                            flipGuard: _flipGuard,
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
