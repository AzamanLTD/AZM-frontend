// =============================================================================
// AZAMAN — HOME PERSISTENT HEADER  (WORKSTREAM A, 2026-10-24)
//
// The Home notification/profile section becomes a pinned, Home-only floating
// header. It is NOT a conventional app bar and it is NOT global: this widget
// exists inside the Home composition only.
//
//   RESTING   — transparent band at the top; nothing paints behind the two
//               controls. Content scrolls UNDER the band; as it does, a
//               restrained translucent surface (tint + blur + hairline)
//               fades in, driven by the REAL scroll offset the Home page
//               feeds [scrollTint] — never by a timer or idle animation.
//   HANDOFF   — the wallet→activity handoff departs the header upward with
//               the rest of the wallet composition (the activity surface
//               owns its own top chrome; the deck peek reads cleanly).
//
//   PULL-DOWN — a downward drag on this bounded band progressively reveals
//               the in-app notification centre from the top edge. The
//               panel follows the finger both directions; release past the
//               threshold commits to open, release before it returns to
//               closed, and a deliberate high-velocity pull commits early.
//               The band is the ONLY gesture surface for this — the Home
//               list's own pull-to-refresh and the Recent Activity handoff
//               are untouched because the band is its own hit region above
//               the scroll view.
//
// Gesture ownership: the band is a full-width, 56px-tall hit surface ABOVE
// the scroll view in the Home Stack. Its vertical-drag recognizer only sees
// pointers that land inside those 56px, so ordinary content scrolling,
// refresh pulls from the content, and the bottom-overscroll activity
// handoff never compete with it. Pointer cancellation, route changes and
// lifecycle events all funnel into the same cancel path — the reveal
// settles closed and the overlay entry is removed.
// =============================================================================

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/auth_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/notification_bell.dart';
import 'package:azaman/widgets/notification_overlay.dart';
import 'package:azaman/widgets/scale_tap.dart';

class HomePersistentHeader extends ConsumerStatefulWidget {
  const HomePersistentHeader({
    super.key,
    required this.onOpenSettings,
    required this.handoff,
    required this.scrollTint,
  });

  final VoidCallback? onOpenSettings;

  /// The wallet→activity handoff progress (0 = wallet rest, 1 = activity
  /// rest). The header departs with it — see the header docs above.
  final Animation<double> handoff;

  /// 0..1 translucency progress driven by the Home scroll offset.
  final ValueListenable<double> scrollTint;

  /// The band's height — also the clearance the Home content reserves.
  static const double bandHeight = 56;

  /// Drag distance that maps to a fully revealed notification centre.
  static const double _openFraction = 0.55;

  /// The reveal fraction at which a release commits to opening.
  static const double _commitReveal = 0.4;

  /// A deliberate downward pull commits at lower distance.
  static const double _commitVelocity = 700;

  @override
  ConsumerState<HomePersistentHeader> createState() =>
      _HomePersistentHeaderState();
}

class _HomePersistentHeaderState extends ConsumerState<HomePersistentHeader> {
  NotificationRevealController? _reveal;
  double _dragDy = 0;
  bool _commitArmed = false;

  /// The raw pointer that owns the live reveal session, and the
  /// cancellation flag it raises. Flutter delivers an ACCEPTED drag's
  /// PointerCancelEvent as onDragEnd (indistinguishable from a release
  /// at the gesture level), so the raw Listener below marks the cancel
  /// first — it sits DEEPER in the band's subtree, so its handleEvent
  /// runs before the recognizer's end callback within the same event
  /// dispatch. The end handler then funnels to the cancel path.
  int? _sessionPointer;
  bool _pointerCancelled = false;

  void _onBandPointerDown(PointerDownEvent e) {
    _sessionPointer ??= e.pointer;
  }

  void _onBandPointerCancel(PointerCancelEvent e) {
    if (_reveal != null && e.pointer == _sessionPointer) {
      _pointerCancelled = true;
    }
  }

  @override
  void dispose() {
    // An interrupted gesture (route change, lifecycle, pointer loss) must
    // never leave a half-revealed panel behind: settle it closed.
    _reveal?.cancel();
    _reveal = null;
    super.dispose();
  }

  double get _openDistance =>
      MediaQuery.sizeOf(context).height * HomePersistentHeader._openFraction;

  void _onDragStart(DragStartDetails _) {
    if (_reveal != null) return;
    _dragDy = 0;
    _commitArmed = false;
    _pointerCancelled = false;
    _reveal = NotificationOverlay.beginReveal(context);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final s = _reveal;
    if (s == null) return;
    _dragDy += d.primaryDelta ?? 0;
    if (_dragDy < 0) _dragDy = 0; // the reveal never dips below closed
    final r = (_dragDy / _openDistance).clamp(0.0, 1.0);
    // One threshold haptic when the pull crosses the commit boundary —
    // the same "meaningful interaction" rule the handoff uses.
    if (!_commitArmed && r >= HomePersistentHeader._commitReveal) {
      _commitArmed = true;
      AzamanHaptics.threshold();
    } else if (_commitArmed && r < HomePersistentHeader._commitReveal) {
      _commitArmed = false;
    }
    s.update(r);
  }

  void _onDragEnd(DragEndDetails d) {
    final s = _reveal;
    _reveal = null;
    if (s == null) return;
    // A raw pointer cancellation (system interruption) arrived with this
    // same event: funnel to the cancel path — never commit on a lost
    // pointer, regardless of threshold or velocity.
    if (_pointerCancelled) {
      _sessionPointer = null;
      s.cancel();
      return;
    }
    _sessionPointer = null;
    final v = d.primaryVelocity ?? 0;
    final r = (_dragDy / _openDistance).clamp(0.0, 1.0);
    if (_commitArmed ||
        r >= HomePersistentHeader._commitReveal ||
        v > HomePersistentHeader._commitVelocity) {
      s.commit();
    } else {
      s.cancel();
    }
  }

  void _onDragCancel() {
    final s = _reveal;
    _reveal = null;
    _sessionPointer = null;
    _pointerCancelled = false;
    s?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    final user = ref.watch(authProvider).user;
    final reduceMotion = !AzMotion.of(context).travel;
    final username = user?.username ?? '';
    final initials = _initials(username);

    final avatarCore = ScaleTap(
      // Opens the SHELL'S settings drawer — see the AzamanHomePage docs.
      onTap: () {
        AzamanHaptics.nav();
        widget.onOpenSettings?.call();
      },
      child: Hero(
        tag: 'profile-avatar',
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.card,
            border: Border.all(
              color: colors.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
    final avatar = reduceMotion
        ? avatarCore
        : avatarCore.animate().scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1, 1),
            duration: 300.ms,
            curve: Curves.easeOutBack,
          );

    // The band: one row, two anchors (notification left, profile right) —
    // the same hierarchy the in-flow header had, now pinned.
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          const NotificationBell(),
          const Spacer(),
          Semantics(button: true, label: 'Profile and settings', child: avatar),
        ],
      ),
    );

    Widget band = SizedBox(
      key: const ValueKey('home-persistent-header'),
      height: HomePersistentHeader.bandHeight,
      child: Stack(
        children: [
          // The translucent surface — mounted only once the scroll tint
          // exists, so the resting band paints nothing at all and the
          // blur never runs at rest.
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: widget.scrollTint,
                builder: (context, tint, _) {
                  if (tint <= 0.01) return const SizedBox.shrink();
                  return ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 18 * tint,
                        sigmaY: 18 * tint,
                      ),
                      child: DecoratedBox(
                        key: const ValueKey('home-header-surface'),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.78 * tint),
                          border: Border(
                            bottom: BorderSide(
                              color: colors.border.withValues(
                                alpha: 0.6 * tint,
                              ),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          controls,
        ],
      ),
    );

    // Entrance: the same block-0 choreography the in-flow header had —
    // identity arrives from the left. Removed under reduced motion.
    if (!reduceMotion) {
      band = band
          .animate()
          .fadeIn(duration: MotionTokens.control, curve: MotionTokens.enter)
          .slideX(
            begin: -0.04,
            end: 0,
            duration: MotionTokens.control,
            curve: MotionTokens.enter,
          );
    }

    // The bounded pull-down surface, then the handoff departure on top.
    final draggable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _onDragCancel,
      // Raw pointer plumbing (see _onBandPointerCancel): sits deeper than
      // the GestureDetector so its cancel marks the session BEFORE the
      // recognizer's end callback reads the flag.
      child: Listener(
        // Opaque: the band's own subtree is sparsely hit-testable, and
        // deferToChild would starve the listener of the raw events.
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onBandPointerDown,
        onPointerCancel: _onBandPointerCancel,
        child: band,
      ),
    );

    return AnimatedBuilder(
      animation: widget.handoff,
      builder: (context, _) {
        final t = widget.handoff.value;
        return IgnorePointer(
          ignoring: t > 0.01,
          child: Opacity(
            opacity: 1 - t,
            child: Transform.translate(
              offset: Offset(0, -(HomePersistentHeader.bandHeight + 12) * t),
              child: draggable,
            ),
          ),
        );
      },
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'A';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }
}
