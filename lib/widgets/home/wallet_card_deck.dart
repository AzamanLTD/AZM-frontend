// =============================================================================
// AZAMAN — WALLET CARD DECK  (Home §4, wallet-pouch evolution — 2026-10-16)
//
// Evolves the pull-reveal deck (binary tucked/revealed, vertical pull to
// open) into the wallet-pouch interaction:
//
//   * TUCKED (default): BOTH cards sit behind an opaque leather pouch. The
//     balance card is the primary front card; the Visa card peeks out above
//     it. No amount, GHS equivalent, FX rate, delta chip or other financial
//     value is exposed — the pouch is the default privacy state.
//   * TAP a card's exposed header (or the selector row) to bring that card
//     out of the pouch: balanceOut or visaOut.
//   * SWIPE UP on an extracted card to return it to the pouch (tucked).
//     Opening is tap-only, so one directional gesture never means both
//     opening and closing (the contract's deliberate-gesture requirement).
//   * Switching between cards (either state, or via the selector row) is a
//     continuous handoff — one pose tween, no independent card animations.
//
// ONE AnimationController drives everything: the selected card, the pouch
// mouth/front, the foreground depth and the contact shadow share a single
// pose interpolation. There is no second clock.
//
// The deck stays a gesture/presentation surface: what "out" means
// downstream (the Visa PIN gate, the details panel) belongs to the HOME
// HOST via [onStateChanged] and [tuck] — same contract as before.
//
// Accessibility: while tucked, the obscured card content is excluded from
// semantics entirely; the two selectors ("Reveal balance card" / "Open AZM
// Visa card") and the always-available selector row carry the semantics.
//
// Reduced motion: no spring traversal — pose lands directly on the target.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/home/wallet_pocket_surface.dart';

/// The deck's authoritative state.
enum WalletDeckState { tucked, balanceOut, visaOut }

/// Pure geometry of one deck state. Public so tests can pin the layered
/// relationship without pumping pixels.
class WalletDeckPose {
  const WalletDeckPose({
    required this.visaTop,
    required this.balanceTop,
    required this.mouthY,
    required this.visaScale,
    required this.balanceScale,
    required this.visaShadow,
    required this.balanceShadow,
  });

  /// Top of the Visa card within the deck window.
  final double visaTop;

  /// Top of the balance card within the deck window.
  final double balanceTop;

  /// Top of the pouch mouth within the deck window.
  final double mouthY;

  final double visaScale;
  final double balanceScale;

  /// Contact-shadow alpha for each card (0..1 scale factor).
  final double visaShadow;
  final double balanceShadow;

  static WalletDeckPose lerp(WalletDeckPose a, WalletDeckPose b, double t) =>
      WalletDeckPose(
        visaTop: a.visaTop + (b.visaTop - a.visaTop) * t,
        balanceTop: a.balanceTop + (b.balanceTop - a.balanceTop) * t,
        mouthY: a.mouthY + (b.mouthY - a.mouthY) * t,
        visaScale: a.visaScale + (b.visaScale - a.visaScale) * t,
        balanceScale: a.balanceScale + (b.balanceScale - a.balanceScale) * t,
        visaShadow: a.visaShadow + (b.visaShadow - a.visaShadow) * t,
        balanceShadow:
            a.balanceShadow + (b.balanceShadow - a.balanceShadow) * t,
      );
}

/// Pure, unit-testable return-gesture physics (the pouch deck's only
/// gesture arithmetic: the swipe-up return while a card is out).
class WalletDeckPhysics {
  const WalletDeckPhysics._();

  /// Upward drag travel (logical px) that maps to the full 0→1 return
  /// progress.
  static const double travelPx = 90;

  /// Fraction of the drag travel at which a release COMMITS the return.
  /// Past the midpoint so accidental micro-swipes never tuck the card.
  static const double commitThreshold = 0.5;

  /// Raw drag distance → return progress [0, 1].
  static double progressFor(double dragPx) {
    if (dragPx <= 0) return 0;
    return (dragPx / travelPx).clamp(0.0, 1.0);
  }

  /// Progress → return fraction with RESISTANCE (ease-in square): a short
  /// swipe nudges the card, it does not flee the pocket.
  static double returnFor(double progress) {
    final p = progressFor(progress * travelPx);
    return p * p;
  }

  /// Whether a release at [progress] commits the return to tucked.
  static bool commits(double progress) => progress >= commitThreshold;
}

/// The two-card wallet deck behind the pouch.
///
/// [balanceCard] is the primary front card; [visaCard] sits behind it and
/// peeks above it while tucked. [onStateChanged] fires whenever the deck's
/// state changes — Home owns the PIN gate and the details panel.
class WalletCardDeck extends StatefulWidget {
  const WalletCardDeck({
    super.key,
    required this.balanceCard,
    required this.visaCard,
    required this.cardHeight,
    this.onStateChanged,
  });

  final Widget balanceCard;
  final Widget visaCard;
  final double cardHeight;

  /// Fired with the deck's NEW state on every committed state change
  /// (selection, return-to-pouch, programmatic [tuck]).
  final ValueChanged<WalletDeckState>? onStateChanged;

  @override
  State<WalletCardDeck> createState() => WalletCardDeckState();
}

/// Public on purpose: the Home host holds a GlobalKey so the PIN-gate
/// flow, the visibility re-lock and the app-lifecycle relock can tuck the
/// deck programmatically (audit §6/§7).
class WalletCardDeckState extends State<WalletCardDeck>
    with SingleTickerProviderStateMixin {
  // ── Geometry constants (derived from the card height) ─────────────────
  // topPad gives the lifted card headroom so it never clips the window top.
  static const double _topPad = 26;

  /// Height of the Visa card's exposed header strip while tucked.
  static const double visaPeek = 44;

  /// Height of the balance card's exposed brand header while tucked.
  static const double balanceHeaderBand = 56;

  /// Pouch body below the balance card's bottom edge.
  static const double _baseLip = 26;

  /// How far an out card lifts (the "emerging" cue).
  static const double _lift = 16;

  /// Pouch overlap left on an out card's very bottom edge (a card pulled
  /// from a pocket keeps its last sliver inside — the full face above it
  /// stays readable).
  static const double _pouchOverlap = 10;

  // Derived slots.
  double get _visaSlot => _topPad;
  double get _balanceSlot => _topPad + visaPeek;
  double get _windowHeight => _balanceSlot + widget.cardHeight + _baseLip;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: MotionTokens.spatial,
    lowerBound: 0,
    upperBound: 1,
  );

  WalletDeckState _state = WalletDeckState.tucked;

  /// Pose captured when the current transition started.
  WalletDeckPose _fromPose = const WalletDeckPose(
    visaTop: _topPad,
    balanceTop: _topPad + visaPeek,
    mouthY: _topPad + visaPeek + balanceHeaderBand,
    visaScale: 0.96,
    balanceScale: 1.0,
    visaShadow: 0.06,
    balanceShadow: 0.22,
  );
  late WalletDeckPose _targetPose;

  /// Live return-gesture progress (raw) while dragging.
  double _dragProgress = 0;
  bool _hapticArmed = false;

  /// The LIVE pose captured at drag start. The return gesture interpolates
  /// from HERE (where the card actually is under the finger), never from a
  /// settled pose the spring may not have reached yet — a grab mid-emergence
  /// returns from the grabbed position, not from a stale target.
  WalletDeckPose? _dragBasePose;

  /// The tucked balance hit-target's opacity endpoints for the current
  /// transition: 1 settled-tucked, 0 settled-out. The target itself is
  /// INVISIBLE (a transparent tap/semantics layer over the real card's
  /// exposed header — see _TuckedBalanceHitTarget); this fade only gates
  /// whether it may intercept touches, so it never visibly pops.
  double _fromHeader = 1.0;
  double _toHeader = 1.0;

  double get _headerFade =>
      _fromHeader + (_toHeader - _fromHeader) * _eased(_ctrl.value);

  @override
  void initState() {
    super.initState();
    _targetPose = _fromPose;
    _targetPose = _poseFor(WalletDeckState.tucked);
    _fromPose = _targetPose;
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  WalletDeckState get state => _state;
  bool get isTucked => _state == WalletDeckState.tucked;

  // ── Poses ───────────────────────────────────────────────────────────────

  WalletDeckPose _poseFor(WalletDeckState s) {
    final h = widget.cardHeight;
    switch (s) {
      case WalletDeckState.tucked:
        return WalletDeckPose(
          visaTop: _visaSlot,
          balanceTop: _balanceSlot,
          mouthY: _balanceSlot + balanceHeaderBand,
          visaScale: 0.96,
          balanceScale: 1.0,
          visaShadow: 0.06,
          balanceShadow: 0.22,
        );
      case WalletDeckState.balanceOut:
        return WalletDeckPose(
          visaTop: _visaSlot + 60, // sinks fully behind the pouch
          balanceTop: _balanceSlot - _lift,
          mouthY: _balanceSlot - _lift + h - _pouchOverlap,
          visaScale: 0.94,
          balanceScale: 1.0,
          visaShadow: 0.02,
          balanceShadow: 0.34, // lifted: stronger contact shadow
        );
      case WalletDeckState.visaOut:
        return WalletDeckPose(
          visaTop: _visaSlot - _lift,
          // The concealed balance card sinks to the deck window's FLOOR
          // (`windowHeight - cardHeight`): flush with the window's bottom
          // edge rather than beyond it. The old +130 offset placed its
          // bottom 104px below the window, and with Clip.none layers that
          // spilled the hidden card over Home's content and the selector
          // row. At the floor the card is still fully covered — the
          // lifted Visa card (full width, drawn in front from y=10)
          // hides its sliver above the pouch mouth, and the opaque pouch
          // hides the rest.
          balanceTop: _balanceSlot + _baseLip,
          mouthY: _visaSlot - _lift + h - _pouchOverlap,
          visaScale: 1.0,
          balanceScale: 0.94,
          visaShadow: 0.34,
          balanceShadow: 0.02,
        );
    }
  }

  /// The pose currently being presented (transition interpolation).
  WalletDeckPose get currentPose =>
      WalletDeckPose.lerp(_fromPose, _targetPose, _eased(_ctrl.value));

  static double _eased(double t) =>
      Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

  // ── State changes ──────────────────────────────────────────────────────

  /// Select a new state (tap on a selector or the selector row). A
  /// continuous handoff: one pose tween from wherever the deck is.
  ///
  /// TOGGLE-TO-TUCK (PR #154 review): tapping the selector of the card
  /// that is ALREADY out re-tucks the deck — the same deliberate
  /// selection gesture as the swipe-up return, for users who never
  /// discover the swipe. Selecting the OTHER card still switches
  /// directly. The re-tuck travels the same [_transitionTo] →
  /// [Widget.onStateChanged] path as every return, so the Home host
  /// clears the PIN gate and sensitive details exactly as it does for
  /// the swipe.
  void select(WalletDeckState target) {
    if (target == _state) {
      if (target == WalletDeckState.tucked) return; // already home
      AzamanHaptics.selection();
      _transitionTo(WalletDeckState.tucked);
      return;
    }
    AzamanHaptics.selection();
    _transitionTo(target);
  }

  void _transitionTo(WalletDeckState target) {
    _fromPose = currentPose;
    _fromHeader = _headerFade;
    _targetPose = _poseFor(target);
    _toHeader = target == WalletDeckState.tucked ? 1.0 : 0.0;
    _state = target;
    widget.onStateChanged?.call(target);
    if (_reduceMotion) {
      _ctrl.value = 1.0; // direct transition, same semantics
    } else {
      _ctrl.value = 0;
      _ctrl.animateWith(_springTo(1));
    }
  }

  /// Return the deck to the pouch (upward swipe commit, programmatic
  /// re-lock, failed/cancelled PIN gate, app backgrounding).
  void tuck() {
    if (_state == WalletDeckState.tucked) return;
    if (_hapticArmed) {
      AzamanHaptics.threshold();
      _hapticArmed = false;
    }
    _transitionTo(WalletDeckState.tucked);
  }

  /// Back-compat alias for the pre-pouch deck's host contract.
  void collapse() => tuck();

  SpringSimulation _springTo(double end) {
    // Same deliberate card feel as the original deck: moderately stiff,
    // lightly damped — catches and settles without oscillating.
    const spring = SpringDescription(mass: 1, stiffness: 380, damping: 26);
    return SpringSimulation(spring, _ctrl.value, end, _ctrl.velocity * 0.4);
  }

  // ── The return gesture (swipe UP while a card is out) ──────────────────
  // Opening is tap-only: the vertical drag is state-aware and only acts
  // when a card is already out, so the same directional gesture can never
  // mean both opening and closing, and a tucked deck never blocks the
  // surrounding scroll view.

  void _onDragStart(DragStartDetails _) {
    _hapticArmed = true;
    _dragProgress = 0;
    // POSE CONTINUITY: capture the pose EXACTLY as rendered at the moment
    // of the grab. If a spring is still in flight the card is frozen mid-
    // travel (no snap, no continued drift under the finger) and the return
    // gesture works from this live pose — never from a settled pose the
    // spring had not reached.
    final live = currentPose;
    final liveHeader = _headerFade;
    if (_ctrl.isAnimating) {
      _ctrl.stop();
      setState(() {
        _fromPose = live;
        _targetPose = live;
        _fromHeader = liveHeader;
        _toHeader = liveHeader;
        _ctrl.value = 1.0; // lerp(live, live) holds the live pose
      });
    }
    _dragBasePose = live;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_state == WalletDeckState.tucked)
      return; // unreachable: tucked has null callbacks
    final dy = -d.delta.dy; // up (negative dy) returns the card
    if (dy <= 0) return; // a downward drag while out: ignore (no flip risk)
    _dragProgress = WalletDeckPhysics.progressFor(
      _dragProgress * WalletDeckPhysics.travelPx + dy,
    );
    // Interpolate from the GRABBED pose toward tucked with resistance —
    // same pose system, no second clock.
    final returnT = WalletDeckPhysics.returnFor(_dragProgress);
    setState(() {
      _ctrl.value = 0; // freeze the tween; pose derived below
      _targetPose = _poseFor(_state);
      _fromPose = WalletDeckPose.lerp(
        _dragBasePose ?? _poseFor(_state),
        _poseFor(WalletDeckState.tucked),
        returnT,
      );
      // The tucked overlay fades back in proportionally to the return.
      _fromHeader = returnT;
      _toHeader = returnT;
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_state == WalletDeckState.tucked) {
      _dragProgress = 0;
      _dragBasePose = null;
      return;
    }
    final commitsNow = WalletDeckPhysics.commits(_dragProgress);
    _dragProgress = 0;
    _dragBasePose = null;
    if (commitsNow) {
      tuck();
    } else {
      // Below threshold: spring back to the out pose FROM THE LIVE POSE —
      // a plain grab-and-release (no upward movement) must hold the pose
      // where it is and settle, never snap toward a stale pre-drag pose.
      final live = currentPose;
      final liveHeader = _headerFade;
      if (_reduceMotion) {
        setState(() {
          _fromPose = live;
          _targetPose = _poseFor(_state);
          _fromHeader = liveHeader;
          _toHeader = 0.0;
          _ctrl.value = 1.0;
        });
      } else {
        setState(() {
          _fromPose = live;
          _targetPose = _poseFor(_state);
          _fromHeader = liveHeader;
          _toHeader = 0.0;
          _ctrl.value = 0;
        });
        _ctrl.animateWith(_springTo(1));
      }
    }
  }

  /// The Visa card slot. Paint order (front/back) is decided by the
  /// caller — see the card Stack's z-order note in [build].
  Widget _visaCardSlot(WalletDeckPose pose, double h) {
    return Positioned(
      key: const ValueKey('wallet-deck-visa-slot'),
      top: pose.visaTop,
      left: 0,
      right: 0,
      height: h,
      child: ExcludeSemantics(
        excluding: _state != WalletDeckState.visaOut,
        child: Transform.scale(
          scale: pose.visaScale,
          child: _CardShell(
            shadow: pose.visaShadow,
            radius: 22,
            child: widget.visaCard,
          ),
        ),
      ),
    );
  }

  /// The balance card slot. Paint order (front/back) is decided by the
  /// caller — see the card Stack's z-order note in [build].
  Widget _balanceCardSlot(WalletDeckPose pose, double h) {
    return Positioned(
      key: const ValueKey('wallet-deck-balance-slot'),
      top: pose.balanceTop,
      left: 0,
      right: 0,
      height: h,
      child: ExcludeSemantics(
        excluding: _state != WalletDeckState.balanceOut,
        child: Transform.scale(
          scale: pose.balanceScale,
          child: _CardShell(
            shadow: pose.balanceShadow,
            radius: 24,
            child: widget.balanceCard,
          ),
        ),
      ),
    );
  }

  // ── BUILD ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pose = currentPose;
    final tucked = isTucked;
    final h = widget.cardHeight;
    final windowH = _windowHeight;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          // GESTURE ARBITRATION: the vertical drag exists ONLY to return an
          // out card. While tucked the callbacks are NULL (not merely
          // early-returning): with no recognizers registered the deck never
          // enters the vertical-drag arena, so a drag over the tucked deck
          // is won outright by Home's scrollable — the cards can never
          // swallow a page scroll.
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: tucked ? null : _onDragStart,
          onVerticalDragUpdate: tucked ? null : _onDragUpdate,
          onVerticalDragEnd: tucked ? null : _onDragEnd,
          child: SizedBox(
            key: const ValueKey('wallet-deck-window'),
            height: windowH,
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ── The two cards. PER-CARD semantics privacy: a card's
                //    content is excluded from accessibility whenever THAT
                //    card is covered — the balance card is covered in
                //    tucked AND visaOut; the Visa card is covered in
                //    tucked AND balanceOut. Only the selected, exposed
                //    card publishes its content, so an obscured amount or
                //    card face can never leak to a screen reader.
                Stack(
                  key: const ValueKey('wallet-deck-card-stack'),
                  clipBehavior: Clip.none,
                  // Z-ORDER: state-aware paint order. A Stack paints its
                  // children in list order, so the SELECTED card is always
                  // last in the list and therefore always paints over the
                  // other. In visaOut the Visa card must render above the
                  // concealed balance card — otherwise the balance card
                  // (sliding down to its concealed pose) overlaps and
                  // paints across the lower portion of the selected Visa
                  // card before the pouch covers it, and the selection
                  // reads as two broken half-cards instead of one complete
                  // selected card. In tucked and balanceOut the physical
                  // hierarchy is unchanged: balance is the foreground
                  // card, with the Visa header exposed behind it.
                  children: _state == WalletDeckState.visaOut
                      ? [_balanceCardSlot(pose, h), _visaCardSlot(pose, h)]
                      : [_visaCardSlot(pose, h), _balanceCardSlot(pose, h)],
                ),
                // ── Tucked balance hit-target: a TRANSPARENT tap +
                //    semantics layer over the real card's exposed header
                //    band (the card's own brand row — logo, "Azaman
                //    Balance", public AZM ID — is what shows above the
                //    pouch mouth; there is no separately painted header
                //    to duplicate or obscure its corners). It exists only
                //    while tucked so a header tap SELECTS the balance card
                //    (and never flips the card beneath); once the card is
                //    out, its own gestures own the surface.
                if (tucked)
                  Positioned(
                    key: const ValueKey('wallet-tucked-balance-header'),
                    top: _balanceSlot,
                    left: 0,
                    right: 0,
                    height: balanceHeaderBand,
                    child: _TuckedBalanceHitTarget(
                      onTap: () => select(WalletDeckState.balanceOut),
                    ),
                  ),
                // ── The Visa strip selector: the Visa card's exposed
                //    header band while tucked.
                if (tucked)
                  Positioned(
                    key: const ValueKey('wallet-visa-strip'),
                    top: _visaSlot,
                    left: 0,
                    right: 0,
                    height: visaPeek,
                    child: _VisaStripSelector(
                      onTap: () => select(WalletDeckState.visaOut),
                    ),
                  ),
                // ── THE POUCH — topmost physical layer. Always opaque and
                //    always absorbs taps: concealed card content can never
                //    be pressed through it (audit §6).
                Positioned(
                  key: const ValueKey('wallet-pouch-surface'),
                  // 8px of headroom above the mouth so the painter's
                  // contact shadow (cast up onto the cards) has room.
                  top: pose.mouthY - 8,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // A physical surface: taps on the pocket do nothing —
                    // concealed card content can never be pressed through.
                    onTap: () {},
                    child: WalletPocketSurface(mouthY: 8, dark: dark),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AzSpace.md),
        // ── SELECTOR ROW — always available, accessible switching between
        //    both cards from every state (and the guaranteed hit target
        //    for the rear card while tucked).
        _CardSelectorRow(
          state: _state,
          onSelectBalance: () => select(WalletDeckState.balanceOut),
          onSelectVisa: () => select(WalletDeckState.visaOut),
        ),
      ],
    );
  }
}

/// The painted contact shadow + rounded shell around one card in the deck.
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.shadow,
    required this.radius,
    required this.child,
  });

  final double shadow;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22 * (0.2 + shadow)),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The tucked balance header's transparent hit-target. The VISIBLE header
/// is the balance card's own brand row (its top band shows above the pouch
/// mouth — same rounded corners, same PremiumCardRim); this layer only
/// (a) turns a header tap into a balance-card selection (never the card's
/// own flip, which belongs to the out state) and (b) publishes the
/// accessible "Reveal balance card" control. It paints NOTHING — no fill,
/// no corners, no second logo — so the exposed header is literally the
/// physical card, at both tucked and out.
class _TuckedBalanceHitTarget extends StatelessWidget {
  const _TuckedBalanceHitTarget({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Reveal balance card',
        excludeSemantics: true,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The Visa card's exposed strip while tucked — its guaranteed, accessible
/// selection target (the rear card is genuinely selectable, never a 20px
/// sliver).
class _VisaStripSelector extends StatelessWidget {
  const _VisaStripSelector({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Open AZM Visa card',
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Compact two-option selector row below the deck. Always active, so
/// switching cards is a continuous handoff from any state, and the rear
/// card always has a real hit target (44px chips).
class _CardSelectorRow extends StatelessWidget {
  const _CardSelectorRow({
    required this.state,
    required this.onSelectBalance,
    required this.onSelectVisa,
  });

  final WalletDeckState state;
  final VoidCallback onSelectBalance;
  final VoidCallback onSelectVisa;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SelectorChip(
          key: const ValueKey('wallet-select-balance'),
          label: 'Balance',
          // Screen-reader labels stay the deck's full-sentence controls;
          // only the VISIBLE chip text shortens (PR #154 review).
          semanticsLabel: 'Reveal balance card',
          active: state == WalletDeckState.balanceOut,
          activeColor: scheme.primary,
          onTap: onSelectBalance,
        ),
        const SizedBox(width: AzSpace.sm),
        _SelectorChip(
          key: const ValueKey('wallet-select-visa'),
          label: 'Visa',
          semanticsLabel: 'Open AZM Visa card',
          active: state == WalletDeckState.visaOut,
          activeColor: scheme.primary,
          onTap: onSelectVisa,
        ),
      ],
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;

  /// The full, meaningful a11y sentence — the visible label may be a
  /// shortened word, but screen readers announce the whole control.
  final String semanticsLabel;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: active
            ? activeColor.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: AzSpace.xl,
              vertical: AzSpace.xs + 2,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: active ? activeColor : scheme.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
