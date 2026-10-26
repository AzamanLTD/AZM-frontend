// =============================================================================
// PROFILE JOYSTICK — the shared directional joystick for business profile
// avatars (Workstream A, 2026-10-26).
//
// ONE interaction component, attached to BOTH the marketplace listing
// avatar (BusinessResultCard) and the storefront hero avatar
// (MarketStorefrontShell), so the two hosts can never drift apart into
// incompatible gesture systems.
//
// Contract (owner spec, 2026-10-26):
//   * Touch-down starts the interaction. NO long press is required.
//   * Four cardinal directions, deterministic dominant-axis selection:
//       up    -> menu      (real catalog destination only)
//       down  -> story     (only when the authoritative contract says an
//                          active story exists)
//       right -> bookmark  (the durable toggleBusinessSaved seam)
//       left  -> show-less (MANDATORY confirmation, then the real
//                          RecommendationFeedbackService apply/undo)
//   * Activation slop: ~16 logical px (spec range 14-20, tuned by tests).
//     A small dead zone + axis hysteresis stop finger tremor from
//     thrashing the selection.
//   * Gesture-arena arbitration: a gesture that begins on the avatar
//     becomes a joystick gesture after the small activation displacement
//     (it wins the arena BEFORE the parent vertical-scroll recogniser's
//     18px touch slop can claim it), so an active joystick never also
//     scrolls the marketplace feed or opens the profile. Scrolling that
//     begins OUTSIDE the avatar is untouched.
//   * A no-movement release preserves the existing short-tap behaviour
//     ([onTap] — the listing action panel); a cancelled/lost gesture, a
//     second pointer, or route disposal closes the dial WITHOUT
//     performing an action and without leaving stuck state.
//   * Haptics: one selection haptic ONLY when the highlighted direction
//     CHANGES (never per pointer update), and exactly one confirmation
//     haptic per executed action. Opening and closing are silent.
//   * Reduced motion (MediaQuery.disableAnimations): the dial appears and
//     closes instantly — no springs, no perpetual animations.
//   * The dial is anchored on the avatar's REAL global rect (never a
//     guessed offset) and rides the ROOT overlay so satellites may
//     extend outside the card without being clipped by the card,
//     scroll viewport, sheet, or parent stack. Satellites are display
//     only (IgnorePointer): selection is by movement, never by tapping a
//     satellite, so no action can fire twice from one pointer sequence.
//   * Physical directions (drag right = bookmark) in BOTH text
//     directions: the mapping is muscle memory, not reading order.
// =============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

/// The four cardinal shortcuts, in the spec's fixed mapping.
enum ProfileJoystickDirection { menu, story, bookmark, showLess }

/// Pure direction classifier — the spec's sketch, made deterministic.
///
/// Returns null inside the activation dead zone (displacement below
/// [activationSlop]); otherwise the DOMINANT AXIS wins (ties go
/// vertical, matching the sketch's `>` comparisons), and the sign picks
/// the direction within that axis.
ProfileJoystickDirection? directionFor(
  Offset delta, {
  double activationSlop = 16.0,
}) {
  if (delta.distance < activationSlop) return null;
  if (delta.dx.abs() > delta.dy.abs()) {
    return delta.dx > 0
        ? ProfileJoystickDirection.bookmark
        : ProfileJoystickDirection.showLess;
  }
  return delta.dy < 0
      ? ProfileJoystickDirection.menu
      : ProfileJoystickDirection.story;
}

/// One direction's delegate + honest availability.
///
/// [onRelease] == null means the shortcut is genuinely unavailable for
/// this business right now: the satellite renders dimmed and a release
/// on it fires NOTHING (no dead delegates, no faked success).
class ProfileJoystickAction {
  const ProfileJoystickAction({
    required this.icon,
    required this.label,
    this.onRelease,
    this.unavailableLabel = 'Unavailable',
  });

  final IconData icon;
  final String label;
  final VoidCallback? onRelease;
  final String unavailableLabel;

  bool get available => onRelease != null;
}

/// The delegate bundle the hosts pass in. Nothing is invented here:
/// every callback must be the host's real seam.
class ProfileJoystickActions {
  const ProfileJoystickActions({
    required this.menu,
    required this.story,
    required this.bookmark,
    required this.showLess,
  });

  final ProfileJoystickAction menu;
  final ProfileJoystickAction story;
  final ProfileJoystickAction bookmark;
  final ProfileJoystickAction showLess;

  ProfileJoystickAction actionFor(ProfileJoystickDirection direction) {
    switch (direction) {
      case ProfileJoystickDirection.menu:
        return menu;
      case ProfileJoystickDirection.story:
        return story;
      case ProfileJoystickDirection.bookmark:
        return bookmark;
      case ProfileJoystickDirection.showLess:
        return showLess;
    }
  }
}

/// The shared joystick widget. Wraps the avatar ([child]) and installs
/// the arena-participating recogniser; the dial rides the root overlay.
class ProfileJoystick extends ConsumerStatefulWidget {
  const ProfileJoystick({
    super.key,
    required this.child,
    required this.actions,
    this.onTap,
    this.semanticLabel = 'Business quick actions',
    this.semanticHint =
        'Touch, then drag: up for menu, down for story, right to '
        'bookmark, left to show less. Tap for more actions.',
    this.activationSlop = 16.0,
  });

  /// The avatar (its own hit-test target).
  final Widget child;

  final ProfileJoystickActions actions;

  /// Preserved short-tap behaviour — the existing listing action panel.
  /// Null on hosts where a plain tap has no action.
  final VoidCallback? onTap;

  final String semanticLabel;
  final String semanticHint;

  /// Spec range 14-20 logical px; 16 tuned with the widget tests.
  final double activationSlop;

  @override
  ConsumerState<ProfileJoystick> createState() => _ProfileJoystickState();
}

class _ProfileJoystickState extends ConsumerState<ProfileJoystick> {
  // Required dominance margin before the dominant axis may flip —
  // hysteresis against diagonal finger tremor.
  static const double _axisSwitchMargin = 4.0;

  _JoystickSession? _session;
  int? _activePointer;
  bool _globalRouteActive = false;

  void _installGlobalRoute() {
    if (_globalRouteActive) return;
    _globalRouteActive = true;
    GestureBinding.instance.pointerRouter
        .addGlobalRoute(_onGlobalPointerEvent);
  }

  void _uninstallGlobalRoute() {
    if (!_globalRouteActive) return;
    _globalRouteActive = false;
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_onGlobalPointerEvent);
  }

  bool get _reducedMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  // ── Session lifecycle ─────────────────────────────────────────────────

  void _sessionStart(int pointer) {
    if (_session != null) return; // one live session only
    final anchor = _anchorRect();
    if (anchor == null) return;
    final colors = ref.read(themeProvider).colors;
    final reducedMotion = _reducedMotion;
    final session = _JoystickSession();
    session.entry = OverlayEntry(
      builder: (_) => _JoystickOverlay(
        anchor: anchor,
        actions: widget.actions,
        direction: session.direction,
        reducedMotion: reducedMotion,
        colors: colors,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(session.entry);
    _session = session;
    _activePointer = pointer;
    _installGlobalRoute();
    setState(() {}); // avatar pressed state
  }

  void _sessionDirectionChanged(ProfileJoystickDirection? direction) {
    final session = _session;
    if (session == null || session.direction == direction) return;
    session.direction = direction;
    if (direction != null) {
      // ONE selection haptic per CHANGE — never per pointer update.
      AzamanHaptics.selection();
    }
    session.entry.markNeedsBuild();
  }

  void _sessionReleased(ProfileJoystickDirection? direction) {
    final session = _session;
    _closeSession();
    if (session == null || session.cancelled) return;
    if (direction == null) {
      // No meaningful movement — the preserved short-tap behaviour.
      widget.onTap?.call();
      return;
    }
    final action = widget.actions.actionFor(direction);
    if (action.onRelease == null) return; // unavailable: no dead fire
    // EXACTLY one confirmation haptic per executed action.
    AzamanHaptics.confirm();
    action.onRelease!();
  }

  void _sessionCancelled() {
    if (_session == null) return;
    _session!.cancelled = true;
    _closeSession();
  }

  void _closeSession() {
    final session = _session;
    _session = null;
    _activePointer = null;
    _uninstallGlobalRoute();
    session?.entry.remove();
    if (mounted) setState(() {}); // clear the avatar pressed state
  }

  // A second pointer anywhere on the screen while a joystick session is
  // active cancels it — no action, clean reset.
  void _onGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent &&
        _session != null &&
        event.pointer != _activePointer) {
      _sessionCancelled();
    }
  }

  /// The avatar's REAL global rect — the dial anchors here, never on a
  /// guessed screen offset.
  Rect? _anchorRect() {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    return render.localToGlobal(Offset.zero) & render.size;
  }

  @override
  void dispose() {
    // Route disposal / widget teardown: close WITHOUT performing an
    // action and never leak an overlay entry.
    final session = _session;
    _session = null;
    session?.entry.remove();
    _uninstallGlobalRoute();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _session != null;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _JoystickGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _JoystickGestureRecognizer
              >(
                () => _JoystickGestureRecognizer(
                  debugOwner: this,
                  activationSlop: widget.activationSlop,
                  axisSwitchMargin: _axisSwitchMargin,
                ),
                (recogniser) {
                  recogniser
                    ..onTrackingStart = _sessionStart
                    ..onDirectionChanged = _sessionDirectionChanged
                    ..onReleased = _sessionReleased
                    ..onCancelled = _sessionCancelled;
                },
              ),
        },
        child: AnimatedScale(
          scale: active ? 0.96 : 1.0,
          duration: _reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 110),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Live session bookkeeping. [cancelled] marks a session that must NOT
/// fire on the (still-incoming) release of its original pointer.
class _JoystickSession {
  final List<ProfileJoystickDirection> history = const [];
  ProfileJoystickDirection? direction;
  bool cancelled = false;
  late final OverlayEntry entry;
}

// ── The dial overlay ──────────────────────────────────────────────────────

/// Satellite pill metrics — shared with the width measurement below.
const double _kPillHPad = 12;
const double _kPillIcon = 15;
const double _kPillLabelFs = 12;
const double _kPillVPad = 8;
const double _kPillGap = 10;

/// Display-only satellite fan on the ROOT overlay: four cardinal pills
/// (menu above, story below, bookmark right, show-less left) around the
/// anchored avatar. [IgnorePointer] everywhere — selection is by
/// movement, so no satellite can be tapped into a second action.
class _JoystickOverlay extends StatelessWidget {
  const _JoystickOverlay({
    required this.anchor,
    required this.actions,
    required this.direction,
    required this.reducedMotion,
    required this.colors,
  });

  final Rect anchor;
  final ProfileJoystickActions actions;
  final ProfileJoystickDirection? direction;
  final bool reducedMotion;
  final AzamanColors colors;

  static double _labelWidth(String label) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: _kPillLabelFs,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  double _pillWidth(ProfileJoystickAction action) =>
      _kPillHPad * 2 +
      _kPillIcon +
      6 +
      _labelWidth(
        action.available
            ? action.label
            : '${action.label} (${action.unavailableLabel})',
      );

  double _pillHeight() => _kPillIcon + _kPillVPad * 2;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _satellite(
              ProfileJoystickDirection.menu,
              anchor.topCenter - Offset(0, _kPillGap + _pillHeight() / 2),
            ),
            _satellite(
              ProfileJoystickDirection.story,
              anchor.bottomCenter + Offset(0, _kPillGap + _pillHeight() / 2),
            ),
            _satellite(
              ProfileJoystickDirection.bookmark,
              anchor.centerRight + Offset(_kPillGap + _pillWidth(actions.bookmark) / 2, 0),
            ),
            _satellite(
              ProfileJoystickDirection.showLess,
              anchor.centerLeft - Offset(_kPillGap + _pillWidth(actions.showLess) / 2, 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _satellite(ProfileJoystickDirection d, Offset center) {
    final action = actions.actionFor(d);
    final selected = direction == d;
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 130);
    final pillWidth = _pillWidth(action);
    return Positioned(
      key: ValueKey('joystick-satellite-${d.name}'),
      left: center.dx - pillWidth / 2,
      top: center.dy - _pillHeight() / 2,
      child: AnimatedOpacity(
        duration: duration,
        opacity: action.available ? (selected ? 1.0 : 0.55) : 0.35,
        child: AnimatedScale(
          duration: duration,
          scale: selected ? 1.14 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _kPillHPad,
              vertical: _kPillVPad,
            ),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
                width: selected ? 1.6 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  action.icon,
                  size: _kPillIcon,
                  color: action.available
                      ? (selected ? colors.accent : colors.textPrimary)
                      : colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  action.available
                      ? action.label
                      : '${action.label} (${action.unavailableLabel})',
                  style: TextStyle(
                    fontSize: _kPillLabelFs,
                    fontWeight: FontWeight.w600,
                    color: action.available
                        ? colors.textPrimary
                        : colors.textTertiary,
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

// ── The recogniser ─────────────────────────────────────────────────────────

/// An arena-participating one-pointer recogniser implementing the
/// joystick contract:
///
///   * addAllowedPointer — pointer down: starts tracking AND joins the
///     arena (so the parent scroll recogniser competes with us, and we
///     can WIN it before the scroll's 18px touch slop).
///   * FIRST displacement >= [activationSlop] (any direction): we
///     resolve(accepted) — we win the arena, the parent scroll is
///     rejected, and from here the drag belongs to the joystick.
///   * Later moves: classification with a dead zone (back inside the
///     slop clears the selection) and axis hysteresis.
///   * Pointer up, never accepted: a plain tap — we accept (winning the
///     arena sweep deterministically) and report onReleased(null) so the
///     host preserves its short-tap behaviour.
///   * Pointer up, accepted: onReleased(direction) — the ONE place an
///     action may fire.
///   * Cancel / rejected: onCancelled — no action, full reset.
class _JoystickGestureRecognizer extends OneSequenceGestureRecognizer {
  _JoystickGestureRecognizer({
    required super.debugOwner,
    this.activationSlop = 16.0,
    this.axisSwitchMargin = 4.0,
  });

  /// Spec range 14-20 logical px.
  final double activationSlop;

  /// Required dominance margin before the dominant axis may flip.
  final double axisSwitchMargin;

  // Rewired on every build by the factory handler.
  void Function(int pointer)? onTrackingStart;
  void Function(ProfileJoystickDirection? direction)? onDirectionChanged;
  void Function(ProfileJoystickDirection? direction)? onReleased;
  VoidCallback? onCancelled;

  int? _pointer;
  Offset _down = Offset.zero;
  bool _accepted = false;
  ProfileJoystickDirection? _direction;

  @override
  bool isPointerAllowed(PointerEvent event) => _pointer == null;

  @override
  void addAllowedPointer(PointerEvent event) {
    if (_pointer != null) return; // single-pointer contract
    startTrackingPointer(event.pointer);
    _pointer = event.pointer;
    _down = event.position;
    _accepted = false;
    _direction = null;
    onTrackingStart?.call(event.pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _handleMove(event);
    } else if (event is PointerUpEvent) {
      _handleUp(event);
    } else if (event is PointerCancelEvent) {
      _handleCancel(event);
    }
  }

  void _handleMove(PointerMoveEvent event) {
    final delta = event.position - _down;
    if (!_accepted) {
      if (delta.distance < activationSlop) return; // still dead
      // We win the arena BEFORE the parent scroll's 18px vertical slop
      // can claim it (16 < 18, and euclidean distance dominates any
      // single-axis slippage on diagonals).
      _accepted = true;
      resolve(GestureDisposition.accepted);
    }
    final classified = _classify(delta);
    if (classified != _direction) {
      _direction = classified;
      onDirectionChanged?.call(classified);
    }
  }

  /// Dead zone + dominant-axis classification with hysteresis: the
  /// dominant axis may only flip when it exceeds the current one by
  /// [axisSwitchMargin]; within an axis the sign is already dead-zoned
  /// by the activation slop.
  ProfileJoystickDirection? _classify(Offset delta) {
    if (delta.distance < activationSlop) return null; // dead zone
    final raw = directionFor(delta, activationSlop: activationSlop);
    final current = _direction;
    if (raw == null || current == null) return raw;
    final rawVertical =
        raw == ProfileJoystickDirection.menu ||
        raw == ProfileJoystickDirection.story;
    final currentVertical =
        current == ProfileJoystickDirection.menu ||
        current == ProfileJoystickDirection.story;
    if (rawVertical == currentVertical) return raw; // same axis: follow
    // Axis flip only with clear dominance (hysteresis vs tremor).
    final dominant = rawVertical ? delta.dy.abs() : delta.dx.abs();
    final other = rawVertical ? delta.dx.abs() : delta.dy.abs();
    return dominant > other + axisSwitchMargin ? raw : current;
  }

  void _handleUp(PointerUpEvent event) {
    final direction = _direction;
    final wasAccepted = _accepted;
    if (!wasAccepted) {
      // Plain tap: accept so WE win the sweep deterministically.
      resolve(GestureDisposition.accepted);
    }
    stopTrackingPointer(event.pointer);
    _reset();
    onReleased?.call(wasAccepted ? direction : null);
  }

  void _handleCancel(PointerCancelEvent event) {
    if (!_accepted) {
      resolve(GestureDisposition.rejected);
    }
    stopTrackingPointer(event.pointer);
    _reset();
    onCancelled?.call();
  }

  void _reset() {
    _pointer = null;
    _accepted = false;
    _direction = null;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _reset();
  }

  @override
  String get debugDescription => 'profile joystick';

  @override
  void dispose() {
    _reset();
    super.dispose();
  }
}
