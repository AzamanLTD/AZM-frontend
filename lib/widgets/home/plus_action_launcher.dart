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
import 'package:qr_flutter/qr_flutter.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/az_text.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class PlusLauncherAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const PlusLauncherAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Shared open/close state for the launcher pair (audit §10): the TRIGGER
/// lives structurally beside the bottom nav while the OVERLAY lives in the
/// host's stack, so the two must share one explicit controller instead of
/// the launcher owning both.
class PlusLauncherController extends ChangeNotifier {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  /// UX-CORRECTION §5: the geometry anchor that ties the action group to
  /// the physical + control. The trigger measures its own GLOBAL rect
  /// when it opens and hands it to the controller; the overlay positions
  /// the action group from that measured rect — so the actions visually
  /// ORIGINATE from the plus at any phone size, never a guessed
  /// x-coordinate, never a centered modal column.
  ///
  /// Why measured and NOT a CompositedTransformFollower/LayerLink: the
  /// framework requires the leader to paint BEFORE the follower, but the
  /// trigger lives in the nav band, which paints AFTER the body stack
  /// the overlay lives in — leader-after-follower violates the
  /// LeaderLayer invariant (asserted every frame in debug). Measuring
  /// the rect at open time keeps the exact same anchor contract with
  /// zero layer-order hazards.
  Rect? _triggerRect;
  Rect? get triggerRect => _triggerRect;

  void open({Rect? fromTriggerRect}) {
    _triggerRect = fromTriggerRect ?? _triggerRect;
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
  late final AnimationController _rot = AnimationController(
    vsync: this,
    duration: MotionTokens.standard,
    value: 0,
  );

  void _sync() {
    if (!mounted) return;
    widget.controller.isOpen ? _rot.forward() : _rot.reverse();
    // Rebuild on the controller state change itself: in reduced-motion
    // mode the visual step must land IMMEDIATELY, and `_rot` may have no
    // value distance to travel (a close from value 0 never fires a value
    // notification). The per-tick rebuilds in normal-motion mode come
    // from the AnimatedBuilder listening to `_rot` below.
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final reduceMotion = !AzMotion.of(context).travel;

    // AUDIT (post-merge §2): the trigger rebuilds FROM THE ANIMATION
    // CONTROLLER, not from incidental parent rebuilds. AnimatedBuilder
    // listens to `_rot` directly, so the rotation tracks every tick of
    // the open/close transition in normal-motion mode, and the
    // controller-driven step mapping still applies instantly in
    // reduced-motion mode (`_rot` runs either way; only the mapping
    // differs).
    return AnimatedBuilder(
      animation: _rot,
      builder: (context, _) {
        final open = widget.controller.isOpen;
        final turns = reduceMotion ? (open ? 0.125 : 0.0) : _rot.value * 0.125;
        return Semantics(
          button: true,
          excludeSemantics: true,
          // The trigger is icon-only — the semantic label is the entire
          // affordance. It announces the CURRENT state honestly.
          label: open ? 'Close actions' : 'Open actions',
          child: GestureDetector(
            key: const ValueKey('plus-launcher-trigger'),
            onTap: () {
              if (widget.controller.isOpen) {
                // Dismissal is silent (the liquid-launcher haptic
                // convention).
                widget.controller.close();
              } else {
                AzamanHaptics.nav();
                // §5 anchor: measure MY OWN rect in global coordinates —
                // the overlay positions the group from this.
                final box = context.findRenderObject();
                Rect? rect;
                if (box is RenderBox && box.attached) {
                  rect = box.localToGlobal(Offset.zero) & box.size;
                }
                widget.controller.open(fromTriggerRect: rect);
              }
            },
            child: Container(
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
              child: Transform.rotate(
                angle: turns * 2 * 3.141592653589793,
                child: Icon(Icons.add,
                    color: colors.onAccent, size: widget.size * 0.52),
              ),
            ),
          ),
        );
      },
    );
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
  ConsumerState<PlusActionLauncher> createState() =>
      _PlusActionLauncherState();
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

  /// §5 anchor geometry, measured from the trigger's own rect (see
  /// [PlusLauncherController.triggerRect]). Falls back to the
  /// bottom-right corner of the screen (beside where the + lives) if the
  /// rect is somehow unavailable.
  double _anchorRight(BuildContext context) {
    final local = _localTriggerRect(context);
    if (local == null) return AzSpace.lg;
    final box = context.findRenderObject();
    final width = box is RenderBox && box.attached
        ? box.size.width
        : MediaQuery.sizeOf(context).width;
    return math.max(AzSpace.sm, width - local.right + 6);
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
        return Stack(children: [
          // De-emphasis: dim + blur the content behind the launcher. The
          // scrim fades in with the launcher, so the background reads as
          // going out of focus, not as a modal box.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.controller.isOpen ? _dismiss : null,
              child: FadeTransition(
                opacity: Tween(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(parent: _open, curve: MotionTokens.enter),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8 * t, sigmaY: 8 * t),
                  child: Container(
                    color: colors.background.withValues(alpha: 0.55 * t),
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
          // UX-CORRECTION §5: the actions visually ORIGINATE from the +
          // control. The trigger measured its own rect at open time
          // (controller.triggerRect); the group is Positioned so its
          // bottom-right pins to the trigger's top-right — the column
          // rises from the plus itself and stays right-aligned to the
          // plus-side of the screen. Never centered, never a full-width
          // modal column. Width is bounded (not stretched) so the group
          // reads as an anchored action cluster; the scrim behind still
          // covers the whole screen.
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    MediaQuery.sizeOf(context).width - 2 * AzSpace.lg,
                    300.0,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ]);
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
        : Interval((delayMs / spanMs).clamp(0.0, 0.8), 1.0,
                curve: MotionTokens.enter)
            .transform(t);

    return Opacity(
      opacity: appear,
      child: Transform.translate(
        offset: Offset(0, (1 - appear) * 18),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AzSpace.sm),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.accent.withValues(alpha: 0.16),
                    border:
                        Border.all(color: colors.accent.withValues(alpha: 0.45)),
                  ),
                  child: Icon(action.icon, size: 20, color: colors.accent),
                ),
                const SizedBox(width: AzSpace.md),
                Text(
                  action.label,
                  style: AzText.titleXl.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
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

/// The Receive action's target: shows the user's public AZM ID + a QR so
/// anyone can pay them. No invented amounts, no fake activity — the only
/// data is the user's real public ID.
Future<void> showReceiveSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ReceiveSheet(),
  );
}

class _ReceiveSheet extends ConsumerWidget {
  const _ReceiveSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final azmId = user?.azamanId ?? user?.username ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AzSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Receive money',
              style: AzText.titleXl.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AzSpace.md),
            Text(
              'Share your AZM ID — anyone can send to it.',
              style: AzText.bodyL.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AzSpace.lg),
            Container(
              padding: const EdgeInsets.all(AzSpace.md),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: azmId,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: colors.textPrimary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: AzSpace.lg),
            SelectableText(
              azmId,
              style: AzText.title.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
