// =============================================================================
// AZAMAN — FLOATING PLUS ACTION LAUNCHER  (NEW-HOME §8)
//
// A visually stronger, more vibrant + button beside the bottom nav. When
// tapped the Home content de-emphasizes (dims + blurs out of focus) and the
// action choices appear DIRECTLY on the screen — not inside a large
// rectangular modal/card. The composition reads as the interface opening
// around the +; the + itself becomes the close affordance while open.
//
// Semantic distinction (brief §8): the + launcher means THINGS I CAN DO;
// Recent Activity means THINGS THAT HAPPENED. Keep that clean.
//
// Reusable component: the launcher owns no Home-specific logic. Hosts pass
// [PlusLauncherAction]s; motion/haptics come from the existing system and
// reduced motion is honoured (actions appear immediately, no springs).
// =============================================================================

import 'dart:ui';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/router/route_registry.dart';
import 'package:azaman/providers/money_access_provider.dart';
import 'package:azaman/services/money_unlock.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/az_logo_mark.dart';

class PlusLauncherAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// PASS E (gold hierarchy): bright gold is reserved for the primary
  /// actions (Send / Receive). Secondary actions render a NEUTRAL chip.
  final bool prominent;
  const PlusLauncherAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.prominent = false,
  });
}

/// Shared open/close state for the launcher pair (audit §10): the TRIGGER
/// lives structurally beside the bottom nav while the OVERLAY lives in the
/// host's stack, so the two must share one explicit controller instead of
/// the launcher owning both.
class PlusLauncherController extends ChangeNotifier {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  /// CORRECTION F: the geometry anchor that ties the action cluster to
  /// the physical + control — measured LIVE, every frame. The trigger
  /// tags its own physical button (the 54px Container) with
  /// [triggerKey]; the overlay re-measures that render box on every
  /// build tick, so the cluster tracks the plus even while the nav band
  /// compresses or moves. The frozen open-time rect is kept only as a
  /// fallback for hosts that mount the overlay without the trigger.
  ///
  /// Why measured and NOT a CompositedTransformFollower/LayerLink: the
  /// framework requires the leader to paint BEFORE the follower, but the
  /// trigger lives in the nav band, which paints AFTER the body stack
  /// the overlay lives in — leader-after-follower violates the
  /// LeaderLayer invariant (asserted every frame in debug). Measured
  /// geometry keeps the exact same anchor contract with zero
  /// layer-order hazards.
  final GlobalKey triggerKey = GlobalKey(debugLabel: 'plus-launcher-anchor');

  Rect? _storedTriggerRect;

  /// The LIVE global rect of the physical + button, or the last rect the
  /// trigger reported, or null.
  Rect? get triggerRect {
    final ctx = triggerKey.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.attached) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return _storedTriggerRect;
  }

  void open({Rect? fromTriggerRect}) {
    _storedTriggerRect = fromTriggerRect ?? _storedTriggerRect;
    if (_isOpen) return;
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void toggle() => _isOpen ? close() : open();
}

/// The + trigger. Structurally ADJACENT to the nav ([navigation] [+]) via
/// PremiumBottomNav's `trailing` slot — not an unrelated FAB floating
/// above the bar. The AZM accent identity/theme system colors it: the
/// gradient is the theme's accent pair and the glow is the accent itself,
/// so light/dark/accent behavior follows the user's identity.
class PlusLauncherTrigger extends ConsumerStatefulWidget {
  const PlusLauncherTrigger({
    super.key,
    required this.controller,
    this.size = 54,
  });

  final PlusLauncherController controller;
  final double size;

  @override
  ConsumerState<PlusLauncherTrigger> createState() =>
      _PlusLauncherTriggerState();
}

class _PlusLauncherTriggerState extends ConsumerState<PlusLauncherTrigger>
    with SingleTickerProviderStateMixin {
  /// The single well-owned animation clock for the cumulative logo fill.
  /// 0 = outline-only brand mark; 1 = all three segments filled.
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
    value: 0,
  );

  bool _filling = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _fill.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    // Rebuild on EVERY controller transition — the label ("Open actions" /
    // "Close actions") and the open-state fill must reflect the CURRENT
    // state even when no fill animation is running (reduced motion, or a
    // programmatic open from elsewhere).
    setState(() {});
    if (!widget.controller.isOpen) {
      // Closing/resetting the launcher resets its visual state predictably
      // so the next opening plays the full fill again (never leaves the
      // logo half-filled while the menu is closed).
      _filling = false;
      if (_reduceMotion) {
        _fill.value = 0;
      } else {
        _fill.reverse();
      }
    }
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  bool get _moneyUnlocked => ref.read(moneyAccessProvider).canViewMoney;

  bool get _moneyAuthenticating =>
      ref.read(moneyAccessProvider).isAuthenticating;

  Future<void> _playLogoFill() async {
    if (_filling || widget.controller.isOpen) return;
    _filling = true;
    try {
      await _fill.forward(from: 0);
    } finally {
      _filling = false;
    }
  }

  /// CUMULATIVE bottom-up segment fill (2026-10-12): the logo's BASE
  /// (part3) fills first, then the middle band (part2), then the top peak
  /// (part1). Once a lower segment fills it STAYS filled while the next
  /// segment fills — the Home launcher fill is cumulative, unlike the chat
  /// send button's sequential one-part-at-a-time treatment.
  static double _cumulativeFill(int partFromBottom, double t) {
    const seg = 1.0 / 3;
    // Segment k occupies t = [k*seg, (k+1)*seg); all earlier segments are
    // already fully filled (cumulative), later ones untouched.
    return ((t - partFromBottom * seg) / seg).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) {
        final open = widget.controller.isOpen;
        // While the menu is open the brand mark reads as ACTIVE: fully
        // filled. On close, _sync resets the fill so the next open plays.
        final t = open ? 1.0 : _fill.value;
        return Semantics(
          button: true,
          excludeSemantics: true,
          // The trigger is icon-only — the semantic label is the entire
          // affordance. It announces the CURRENT state honestly.
          label: !_moneyUnlocked
              ? (_moneyAuthenticating ? 'Unlocking' : 'Unlock your money')
              : (open ? 'Close actions' : 'Open actions'),
          child: GestureDetector(
            key: const ValueKey('plus-launcher-trigger'),
            onTap: () async {
              // THE LOCK (owner brief §4): while money is locked this trigger
              // is the unlock affordance. The tap verifies the member, opens
              // the lock and resolves back to the Azaman mark — it does NOT
              // open the actions menu. The next tap does.
              final access = ref.read(moneyAccessProvider);
              if (!access.canViewMoney) {
                if (access.isAuthenticating) return; // one challenge at a time
                final attempt = access.beginUnlock();
                final result = await ref
                    .read(moneyUnlockCoordinatorProvider)
                    .authenticate();
                if (!mounted) return;
                if (result.isSuccess) {
                  access.finishUnlock(attempt);
                  AzamanHaptics.confirm();
                } else {
                  access.cancelUnlock(attempt);
                  AzamanHaptics.selection();
                }
                return;
              }
              if (widget.controller.isOpen) {
                // Dismissal is silent (the liquid-launcher haptic
                // convention).
                widget.controller.close();
                return;
              }
              if (_filling) return; // rapid duplicate taps never stack
              AzamanHaptics.nav();
              if (_reduceMotion) {
                // Reduced motion: same semantics and final state, no
                // travel animation.
                _openFromTrigger();
                return;
              }
              await _playLogoFill();
              if (!mounted) return;
              if (widget.controller.isOpen) return;
              // Only after the FINAL segment completes does the menu open.
              _openFromTrigger();
            },
            child: Container(
              key: widget.controller.triggerKey,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // The AZM accent identity — no hard-coded marketing
                  // colors.
                  colors: [colors.accent, colors.accentSecondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              // The plus glyph is GONE. This is the real AZM brand mark
              // (same geometry/vocabulary as the chat send affordance),
              // rendered as a STATIC 45° clockwise rotation so it reads like
              // a send arrow — the same treatment as the chat send button.
              // The rotation is applied to the mark ONLY, never the clickable
              // container (hit geometry unchanged); it does not animate.
              child: Center(
                child: Transform.rotate(
                  angle: math.pi / 4, // fixed 45° clockwise — no animation
                  child: AzLogoMark(
                    size: Size.square(widget.size * 0.5),
                    outlineColor: colors.onAccent,
                    fillColor: colors.onAccent,
                    fill3: _cumulativeFill(0, t),
                    fill2: _cumulativeFill(1, t),
                    fill1: _cumulativeFill(2, t),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFromTrigger() {
    // §5 anchor: measure MY OWN rect in global coordinates — the overlay
    // positions the group from this.
    final box = context.findRenderObject();
    Rect? rect;
    if (box is RenderBox && box.attached) {
      rect = box.localToGlobal(Offset.zero) & box.size;
    }
    widget.controller.open(fromTriggerRect: rect);
  }
}

/// The launcher OVERLAY layer (scrim + actions). Render it as the topmost
/// Stack child of a host that owns the full screen. The trigger is NOT part
/// of this layer anymore: it sits structurally beside the bottom nav
/// (PremiumBottomNav.trailing) and shares open/close state through
/// [controller]. When open, the actions appear directly over the
/// de-emphasized content; the trigger rotates into its close (×) role in
/// place, in the nav band.
class PlusActionLauncher extends ConsumerStatefulWidget {
  const PlusActionLauncher({
    super.key,
    required this.controller,
    required this.actions,
  });

  final PlusLauncherController controller;
  final List<PlusLauncherAction> actions;

  @override
  ConsumerState<PlusActionLauncher> createState() => _PlusActionLauncherState();
}

class _PlusActionLauncherState extends ConsumerState<PlusActionLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
    reverseDuration: MotionTokens.control,
    value: 0,
  );

  bool _syncedOnce = false;

  @override
  void initState() {
    super.initState();
    // When a closing animation reaches dismissed, the open stack must be
    // UNMOUNTED (not merely faded to opacity 0) — build's closed-at-rest
    // branch only re-evaluates on a state change, so the controller has to
    // hand one over at completion.
    _open.addStatusListener(_onStatus);
    widget.controller.addListener(_onController);
    // NOTE: the initial sync deliberately does NOT happen here —
    // _syncFromController reads AzMotion.of(context), and inherited lookups
    // are illegal before initState completes. didChangeDependencies fires
    // immediately after and before the first build, so a controller that
    // is already open on mount still opens on the launcher's first frame.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_syncedOnce) {
      _syncedOnce = true;
      _syncFromController();
    }
  }

  @override
  void didUpdateWidget(PlusActionLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _open.dispose();
    super.dispose();
  }

  void _onController() => _syncFromController();

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  bool get _reduceMotion => !AzMotion.of(context).travel;

  void _syncFromController() {
    final open = widget.controller.isOpen;
    if (_reduceMotion) {
      // Reduced motion: direct state transition — the actions are simply
      // there, no traversal.
      if (_open.value != (open ? 1.0 : 0.0)) {
        _open.value = open ? 1.0 : 0.0;
        if (mounted) setState(() {});
      }
    } else {
      open ? _open.forward() : _open.reverse();
      // The closed-at-rest build branch renders the bare shrink — the
      // AnimatedBuilder that listens to [_open] is not mounted there, so
      // starting the controller alone schedules NO rebuild. Re-evaluate
      // build here so the animated stack mounts and the traversal plays.
      if (mounted) setState(() {});
    }
  }

  void _dismiss() {
    // Dismissal is silent (the liquid-launcher haptic convention).
    widget.controller.close();
  }

  /// CORRECTION G anchor geometry, measured LIVE from the physical +
  /// button's render box (see [PlusLauncherController.triggerRect]).
  ///
  /// The cluster's RIGHT edge rides the PLUS's own RIGHT edge — not its
  /// center axis — so the cluster's trailing boundary is flush with the
  /// control it opens from, close to the plus/right side of the
  /// viewport, exactly as it is physically positioned. Combined with the
  /// intrinsic-width constraint below (no `stretch`, an [IntrinsicWidth]
  /// cap instead of a bare max-width Column), the cluster can no longer
  /// balloon out to its 300px ceiling and drift toward the opposite side
  /// of the screen — it is only ever as wide as its longest row actually
  /// needs. Falls back to the bottom-right corner of the screen (beside
  /// where the + lives) if the rect is somehow unavailable.
  double _anchorRight(BuildContext context) {
    final local = _localTriggerRect(context);
    if (local == null) return AzSpace.lg;
    final box = context.findRenderObject();
    final width = box is RenderBox && box.attached
        ? box.size.width
        : MediaQuery.sizeOf(context).width;
    final plusRight = local.left + local.width;
    return (width - plusRight).clamp(AzSpace.sm, width - AzSpace.lg);
  }

  double _anchorBottom(BuildContext context) {
    final local = _localTriggerRect(context);
    if (local == null) return AzSpace.navClearanceHeight + AzSpace.lg;
    final box = context.findRenderObject();
    final height = box is RenderBox && box.attached
        ? box.size.height
        : MediaQuery.sizeOf(context).height;
    return math.max(AzSpace.sm, height - local.top + 8);
  }

  Rect? _localTriggerRect(BuildContext context) {
    final trigger = widget.controller.triggerRect;
    if (trigger == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    return trigger.translate(-origin.dx, -origin.dy);
  }

  void _pick(PlusLauncherAction action) {
    // EXACTLY one confirm per pick — the double-haptic class this codebase
    // already removed elsewhere.
    AzamanHaptics.confirm();
    widget.controller.close();
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;

    if (!widget.controller.isOpen && _open.isDismissed) {
      // Closed at rest: the overlay layer is not alive at all (the
      // trigger lives in the nav band and owns its own closed state).
      return const SizedBox.shrink(key: ValueKey('plus-launcher-overlay'));
    }

    return AnimatedBuilder(
      animation: _open,
      builder: (context, _) {
        final t = _open.value;
        return Stack(
          children: [
            // De-emphasis: dim + blur the content behind the launcher. The
            // scrim fades in with the launcher, so the background reads as
            // going out of focus, not as a modal box.
            //
            // PASS G — a MODEST blur: sigma 8 was too aggressive (the whole
            // app read as fogged frosted glass). Sigma 5 + a slightly
            // lighter scrim de-emphasize the background while it stays
            // RECOGNIZABLE: subtle depth separation, not erasure. The scrim
            // stays; the background never goes sharp.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.controller.isOpen ? _dismiss : null,
                child: FadeTransition(
                  opacity: Tween(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(parent: _open, curve: MotionTokens.enter),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5 * t, sigmaY: 5 * t),
                    child: Container(
                      color: colors.background.withValues(alpha: 0.50 * t),
                    ),
                  ),
                ),
              ),
            ),
            // UX-CORRECTION §5: the actions visually ORIGINATE from the +
            // control. The group is a CompositedTransformFollower of the
            // trigger's LayerLink — its bottom-right pins to the trigger's
            // top-right, so the column rises from the plus itself and stays
            // right-aligned to the plus-side of the screen. Never centered,
            // never a full-width modal column. Width is bounded (not
            // stretched) so the group reads as an anchored action cluster;
            // the scrim behind still covers the whole screen.
            // CORRECTION F (geometry fix): the trigger's physical render
            // box is measured LIVE (controller.triggerRect) and the group
            // is Positioned so its bottom edge rises from just above the +
            // and its RIGHT edge is flush with the + button's RIGHT edge
            // (_anchorRight) — the column hangs off the physical plus, on
            // the plus side of the screen, never centered, never a
            // full-width modal column. Width is bounded (not stretched) so
            // the group reads as an anchored action cluster; the scrim
            // behind still covers the whole screen.
            //
            // (Measured geometry, not a LayerLink follower: the trigger
            // lives in the nav band which paints AFTER this body-stack
            // overlay, and the framework requires the leader to paint
            // BEFORE the follower — the link form asserted every frame in
            // debug.)
            Positioned(
              right: _anchorRight(context),
              bottom: _anchorBottom(context),
              child: IgnorePointer(
                ignoring: t < 0.5,
                // CORRECTION G: a bounded INTRINSIC-width cluster. The
                // ConstrainedBox only caps how wide the cluster is ALLOWED
                // to get (so a very long label can't blow past the
                // viewport); it is `IntrinsicWidth` that makes the Column
                // actually size itself to its content instead of
                // ballooning to that cap on every open. `stretch` is gone
                // — each row keeps its own natural width and the Column
                // right-aligns every row to a shared trailing edge, so the
                // rows read as "[ action ]" blocks hanging off the plus,
                // never a full-width mass centered across the screen.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(
                      MediaQuery.sizeOf(context).width - 2 * AzSpace.lg,
                      300.0,
                    ),
                  ),
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < widget.actions.length; i++)
                          _LauncherRow(
                            action: widget.actions[i],
                            index: i,
                            progress: _open,
                            reduceMotion: _reduceMotion,
                            onPick: _pick,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LauncherRow extends ConsumerWidget {
  final PlusLauncherAction action;
  final int index;
  final Animation<double> progress;
  final bool reduceMotion;
  final ValueChanged<PlusLauncherAction> onPick;

  const _LauncherRow({
    required this.action,
    required this.index,
    required this.progress,
    required this.reduceMotion,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final t = progress.value;
    final delayMs = MotionTokens.staggerDelay(index + 2).inMilliseconds;
    final spanMs = MotionTokens.spatial.inMilliseconds;
    final appear = reduceMotion
        ? 1.0
        : Interval(
            (delayMs / spanMs).clamp(0.0, 0.8),
            1.0,
            curve: MotionTokens.enter,
          ).transform(t);

    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(0, (1 - appear) * 18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
            // CORRECTION G: `min` — this row claims only the width its own
            // icon+label need. Combined with the Column's `end` cross-axis
            // alignment, every row's RIGHT edge lands on the same shared
            // trailing line while rows of different label length extend
            // leftward from it by different amounts — "[ action ]" blocks
            // hanging off the plus, not a uniform full-width bar.
            //
            // UX-CORRECTION §5A — text LEFT, icon RIGHT: the icon closes
            // each row on the shared trailing edge (Send|icon, …,
            // Withdraw|icon) so the stack reads as one right-aligned
            // column of actions hanging directly above the plus.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  action.label,
                  style: AzText.titleXl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AzSpace.md),
                Container(
                  key: ValueKey('plus-launcher-chip-${action.label}'),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // PASS E — the gold hierarchy: bright gold chips for
                    // the primary actions only; secondary actions get
                    // neutral gray chips so gold keeps its meaning.
                    color: action.prominent
                        ? colors.accent.withValues(alpha: 0.16)
                        : colors.card.withValues(alpha: 0.8),
                    border: Border.all(
                      color: action.prominent
                          ? colors.accent.withValues(alpha: 0.45)
                          : colors.border,
                    ),
                  ),
                  child: Icon(
                    action.icon,
                    size: 20,
                    color: action.prominent
                        ? colors.accent
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── RECEIVE (things I can DO) ─────────────────────────────────────────────

/// Opens Receive as a full-page route. The historical function name stays
/// stable for existing launcher call sites, but this no longer presents a
/// modal bottom sheet.
Future<void> showReceiveSheet(BuildContext context) async {
  await context.push<void>(AzRoutes.receive);
}
