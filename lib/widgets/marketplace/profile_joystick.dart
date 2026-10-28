// =============================================================================
// PROFILE JOYSTICK — the shared profile interaction for business avatars
// (Workstream A redesign, 2026-10-27: persistent icon-only LIQUID DIAL).
//
// ONE interaction component, attached to BOTH the marketplace listing
// avatar (BusinessResultCard) and the storefront hero avatar
// (MarketStorefrontShell), so the two hosts can never drift apart into
// incompatible gesture systems.
//
// ── The interaction model (owner spec, 2026-10-27) ─────────────────────────
//
// ONE profile gesture session, THREE EXCLUSIVE outcomes. The state
// machine is explicit and deterministic — tap, change your mind, drag
// diagonally, hold too long or swipe the page at the same time can each
// produce exactly one (or zero) outcomes, never two:
//
//   TAP       a short tap on the actual profile image opens the dial in
//             its PERSISTENT, interactive mode. It stays open until an
//             available icon is picked, the anchor is tapped again, or
//             the user taps outside (silent dismissal — the feed below
//             never receives the dismissal tap, and never scrolls).
//   DRAG      a deliberate directional drag opens the same four-icon dial
//             in TRANSIENT gesture mode: the current direction is
//             highlighted, and pointer release executes that direction
//             EXACTLY once. Cancelled pointer, second pointer, or release
//             with no valid direction executes nothing.
//   HOLD      a press-and-hold (platform long-press timing) opens the
//             host's FULL action menu as a bottom sheet. Once recognized,
//             the gesture is CONSUMED — releasing the same pointer fires
//             no tap, no dial and no direction.
//
// The four directions are STABLE so people can learn them:
//   up    -> menu      (the real catalog destination only)
//   down  -> story     (only when the authoritative contract says an
//                       active story exists)
//   right -> bookmark  (the durable toggleBusinessSaved seam)
//   left  -> show-less (MANDATORY confirmation, then the real
//                       RecommendationFeedbackService apply/undo)
// Unavailable directions are never removed or rearranged — the icon
// renders visibly disabled (dimmed) and never executes.
//
// ── Visual language ─────────────────────────────────────────────────────────
//
// The dial reuses the SAME liquid/goo system as the category speed dial
// (CategorySpeedDial → shared DialGooPainter): the goo body visually
// joins the profile anchor to four icon-only circular buttons tightly
// surrounding the photo, with the familiar liquid merge and spring-out
// (satelliteScale / satelliteTravel). No second animation system. The
// avatar photo remains the visible centre of the control — the goo
// anchor is painted as a RING so the photo itself is never covered.
// No text labels appear on the satellites; action names live in the
// accessibility semantics.
//
// ── Honesty contracts preserved from the previous joystick ─────────────────
//
//   * Activation slop ~16px (spec 14-20), dead zone + axis hysteresis.
//   * A gesture that begins on the avatar wins the arena BEFORE the
//     parent vertical-scroll recogniser can claim it; scrolling that
//     begins OUTSIDE the avatar is untouched.
//   * ONE selection haptic per direction CHANGE, exactly ONE
//     confirmation haptic per executed action. Open/close are silent.
//   * Reduced motion: the dial appears and closes instantly.
//   * Unavailable delegates fire nothing; no dead or double fires; the
//     single guarded execution path is shared verbatim by gesture
//     release, persistent-mode icon taps and the accessibility custom
//     actions.
//   * Physical directions in BOTH text directions (muscle memory, not
//     reading order).
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart'
    show kDialGooBody, kDialGooRim;
import 'package:azaman/widgets/liquid/dial_goo_painter.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';
import 'package:azaman/widgets/liquid/liquid_placement.dart';

/// The four cardinal shortcuts, in the spec's fixed mapping.
enum ProfileJoystickDirection { menu, story, bookmark, showLess }

/// Pure direction classifier — deterministic dominant-axis selection.
///
/// Returns null inside the activation dead zone (displacement below
/// [activationSlop]); otherwise the DOMINANT AXIS wins (ties go
/// vertical), and the sign picks the direction within that axis.
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
/// this business right now: the icon renders dimmed and activating it
/// fires NOTHING (no dead delegates, no faked success).
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

// ── Dial metrics ────────────────────────────────────────────────────────────

/// Visible circular icon button diameter. Compact bulges around the
/// photo; the tappable target stays [kDialHitSize].
const double kProfileDialVisualSize = 40.0;

/// Minimum tappable target per the spec — never shrunk to force a fit.
const double kProfileDialHitSize = 44.0;

/// How far the satellite circle may overlap the avatar rim — the goo
/// metaball merge budget. Keeps the ring tight around the photo.
const double kProfileDialGooMerge = 10.0;

/// The satellite icon size (crisp, readable on top of the goo).
const double _kDialIconSize = 20.0;

/// Screen-edge margin for the satellite VISUALS (the dial rides the root
/// overlay, so this guards the physical edge, not any viewport clip).
const double kProfileDialEdgeMargin = 4.0;

// ── Geometry ────────────────────────────────────────────────────────────────

/// Solved dial geometry for one open event: the uniform ring around the
/// anchor and each direction's tappable hit rect (global coordinates).
///
/// The four satellites sit at ONE uniform radius from the dial centre so
/// the ring reads as four equal bulges around the photo — never fitted
/// independently per direction. When the anchor sits too close to a
/// screen edge for the natural ring to fit, the RING (not one satellite)
/// shifts within a capped budget so nothing is clipped and no satellite
/// collides with the avatar; the goo necks absorb the difference.
class ProfileDialGeometry {
  const ProfileDialGeometry({
    required this.center,
    required this.anchorCenter,
    required this.radius,
    required this.hitRects,
  });

  /// Dial ring centre (global).
  final Offset center;

  /// The anchor's centre — satellites fly out from the photo itself.
  final Offset anchorCenter;

  /// Uniform centre-to-satellite-centre distance.
  final double radius;

  /// 44×44 hit rect per direction, centred on the visual circle.
  final Map<ProfileJoystickDirection, Rect> hitRects;

  Rect visualRect(ProfileJoystickDirection d) {
    final hit = hitRects[d]!;
    return Rect.fromCenter(
      center: hit.center,
      width: kProfileDialVisualSize,
      height: kProfileDialVisualSize,
    );
  }

  /// The layer bounds that contain the whole goo scene (anchor + ring +
  /// rim air), used to position and size the painting layer.
  Rect bounds(Rect anchor) {
    var b = anchor;
    for (final rect in hitRects.values) {
      b = b.expandToInclude(rect);
    }
    return b.inflate(56);
  }

  /// Arc slots for the shared goo painter, in launch-stagger order
  /// (menu, story, bookmark, show-less).
  List<ArcSlot> slots() => [
        for (final d in ProfileJoystickDirection.values)
          ArcSlot(
            index: d.index,
            rect: hitRects[d]!,
            angle: _angleFor(d),
          ),
      ];

  static double _angleFor(ProfileJoystickDirection d) {
    switch (d) {
      case ProfileJoystickDirection.menu:
        return -math.pi / 2;
      case ProfileJoystickDirection.story:
        return math.pi / 2;
      case ProfileJoystickDirection.bookmark:
        return 0.0;
      case ProfileJoystickDirection.showLess:
        return math.pi;
    }
  }

  /// Measured, safe-area-aware solve. All inputs are REAL values from
  /// the anchor's global rect and the current MediaQuery — nothing is
  /// guessed or hard-coded per host.
  static ProfileDialGeometry solve({
    required Rect anchor,
    required Size screen,
    required EdgeInsets padding,
  }) {
    final anchorHalf =
        anchor.width >= anchor.height ? anchor.width / 2 : anchor.height / 2;
    const visualHalf = kProfileDialVisualSize / 2;

    // Uniform ring: satellites clear the avatar rim by the goo merge.
    final radius = anchorHalf + visualHalf - kProfileDialGooMerge;

    // Ring shift budget: the ring may move until the nearest satellite
    // has eaten its whole goo-merge overlap with the avatar. Past that
    // the satellite would sit ON the photo — never allowed.
    const shiftBudget = kProfileDialVisualSize; // 40: merge(10) + margin slack

    // Ring position per axis: keep the natural centre, nudged only as
    // far as needed (and never past the shift budget) so the outermost
    // satellite visuals stay inside the screen / safe area. TOTAL for
    // every input: a degenerate anchor (ring wider than the screen)
    // collapses to the best-effort centre instead of throwing.
    //
    // The nudge is one-sided per side (a left-edge misfit can only push
    // the ring right, never left) so no satellite is ever dragged onto
    // the photo beyond the goo merge budget.
    double fitAxis(double natural, double min, double max) {
      if (min > max) return (min + max) / 2; // degenerate: best effort
      if (natural < min) {
        return natural + ((min - natural).clamp(0.0, shiftBudget));
      }
      if (natural > max) {
        return natural - ((natural - max).clamp(0.0, shiftBudget));
      }
      return natural;
    }

    final edge = kProfileDialEdgeMargin + visualHalf + radius;
    final center = Offset(
      fitAxis(anchor.center.dx, edge, screen.width - edge),
      fitAxis(
        anchor.center.dy,
        padding.top + edge,
        screen.height - padding.bottom - edge,
      ),
    );

    Offset centerFor(ProfileJoystickDirection d) {
      switch (d) {
        case ProfileJoystickDirection.menu:
          return center.translate(0, -radius);
        case ProfileJoystickDirection.story:
          return center.translate(0, radius);
        case ProfileJoystickDirection.bookmark:
          return center.translate(radius, 0);
        case ProfileJoystickDirection.showLess:
          return center.translate(-radius, 0);
      }
    }

    return ProfileDialGeometry(
      center: center,
      anchorCenter: anchor.center,
      radius: radius,
      hitRects: {
        for (final d in ProfileJoystickDirection.values)
          d: Rect.fromCenter(
            center: centerFor(d),
            width: kProfileDialHitSize,
            height: kProfileDialHitSize,
          ),
      },
    );
  }
}

/// The shared profile control. Wraps the avatar ([child]) and installs
/// the arena-participating recogniser; the dial rides the root overlay.
class ProfileJoystick extends ConsumerStatefulWidget {
  const ProfileJoystick({
    super.key,
    required this.child,
    required this.actions,
    required this.onLongPress,
    this.semanticLabel = 'Business quick actions',
    this.semanticHint =
        'Tap to open quick actions. Drag up for menu, down for story, '
        'right to save, left to show less. Hold for the full menu.',
    this.activationSlop = 16.0,
  });

  /// The avatar (its own hit-test target).
  final Widget child;

  final ProfileJoystickActions actions;

  /// HOLD outcome: opens the host's FULL action menu as a bottom sheet
  /// (the listing action panel / the storefront shortcuts). Must be the
  /// host's real, complete menu with its real availability conditions.
  final VoidCallback onLongPress;

  final String semanticLabel;
  final String semanticHint;

  /// Spec range 14-20 logical px; 16 tuned with the widget tests.
  final double activationSlop;

  @override
  ConsumerState<ProfileJoystick> createState() => _ProfileJoystickState();
}

// ── The explicit gesture/session state machine ───────────────────────────────

/// One live pointer session on the profile. A session exists only while
/// a finger is down on the avatar; the PERSISTENT dial outlives it.
enum ProfileSessionPhase {
  /// Pointer down, no outcome decided yet (tap / drag / hold pending).
  pressing,

  /// Directional drag won the arena — the transient dial is up.
  dragging,

  /// The long-press fired; the pointer sequence is fully consumed.
  /// No further event from this pointer may produce any outcome.
  consumed,
}

class _ProfileJoystickState extends ConsumerState<ProfileJoystick>
    with SingleTickerProviderStateMixin {
  // Required dominance margin before the dominant axis may flip —
  // hysteresis against diagonal finger tremor.
  static const double _axisSwitchMargin = 4.0;

  /// Identifies the AVATAR subtree so the dial anchors on the real
  /// photo — the joystick's own box can be stretched by tight parent
  /// constraints (e.g. a ListView's cross axis) and is NOT the anchor.
  final GlobalKey _avatarKey = GlobalKey();

  late final AnimationController _dial = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 660),
    reverseDuration: const Duration(milliseconds: 340),
  );

  _Session? _session;
  int? _activePointer;
  bool _globalRouteActive = false;

  // The persistent dial. Null when closed/closing.
  OverlayEntry? _persistentEntry;
  LiquidPhase _persistentPhase = LiquidPhase.closed;
  ProfileDialGeometry? _persistentGeometry;

  bool get _dialOpen =>
      _persistentPhase == LiquidPhase.open ||
      _persistentPhase == LiquidPhase.opening;

  bool get _reducedMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  // ── Global pointer route (second-pointer cancellation) ────────────────────

  void _installGlobalRoute() {
    if (_globalRouteActive) return;
    _globalRouteActive = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
  }

  void _uninstallGlobalRoute() {
    if (!_globalRouteActive) return;
    _globalRouteActive = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _onGlobalPointerEvent,
    );
  }

  // A second pointer anywhere on the screen while a SESSION is active
  // cancels it — no action, clean reset. The persistent dial has no
  // live session and simply keeps its barrier-owned interaction.
  void _onGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent &&
        _session != null &&
        event.pointer != _activePointer) {
      _sessionCancelled();
    }
  }

  // ── Session lifecycle (pressing → dragging / consumed) ───────────────────

  void _sessionStart(int pointer) {
    if (_session != null) return; // one live session only
    _session = _Session(phase: ProfileSessionPhase.pressing);
    _activePointer = pointer;
    _installGlobalRoute();
    setState(() {}); // avatar pressed state
  }

  /// The drag won the arena: open the TRANSIENT dial.
  void _sessionDragStarted() {
    final session = _session;
    if (session == null) return;
    final anchor = _anchorRect();
    if (anchor == null) {
      _sessionCancelled();
      return;
    }
    session.phase = ProfileSessionPhase.dragging;
    session.entry = _buildDialEntry(
      anchor: anchor,
      mode: _DialMode.transient,
      direction: session.direction,
    );
    Overlay.of(context, rootOverlay: true).insert(session.entry!);
    _startDialAnimation();
  }

  void _sessionDirectionChanged(ProfileJoystickDirection? direction) {
    final session = _session;
    if (session == null ||
        session.phase != ProfileSessionPhase.dragging ||
        session.direction == direction) {
      return;
    }
    session.direction = direction;
    if (direction != null) {
      // ONE selection haptic per CHANGE — never per pointer update.
      AzamanHaptics.selection();
    }
    session.entry?.markNeedsBuild();
  }

  /// Pointer release. The ONE place a session outcome may fire:
  /// dragging + a valid available direction executes exactly once;
  /// pressing + no drag is the TAP (persistent dial); consumed fires
  /// nothing (the hold already opened the full menu).
  void _sessionReleased(ProfileJoystickDirection? direction) {
    final session = _session;
    _closeTransientDial();
    if (session == null || session.cancelled) return;
    switch (session.phase) {
      case ProfileSessionPhase.consumed:
        return; // the hold already produced its outcome
      case ProfileSessionPhase.dragging:
        if (direction != null) _executeDirection(direction);
        return;
      case ProfileSessionPhase.pressing:
        _openPersistentDial();
        return;
    }
  }

  /// The platform-timed HOLD: opens the host's full action menu and
  /// consumes the whole pointer sequence.
  void _sessionLongPressed() {
    final session = _session;
    if (session == null || session.phase != ProfileSessionPhase.pressing) {
      return;
    }
    session.phase = ProfileSessionPhase.consumed;
    widget.onLongPress();
  }

  void _sessionCancelled() {
    final session = _session;
    if (session == null) return;
    session.cancelled = true;
    _closeTransientDial();
  }

  void _closeTransientDial() {
    final session = _session;
    _session = null;
    _activePointer = null;
    _uninstallGlobalRoute();
    final entry = session?.entry;
    if (entry != null) {
      _removeEntryWithReverse(entry);
    }
    if (mounted) {
      setState(() {}); // clear the avatar pressed state
    }
  }

  // ── The persistent dial ───────────────────────────────────────────────────

  void _openPersistentDial() {
    if (_dialOpen) return; // re-entrancy guard
    final anchor = _anchorRect();
    if (anchor == null) return;
    final media = MediaQuery.of(context);
    _persistentGeometry = ProfileDialGeometry.solve(
      anchor: anchor,
      screen: media.size,
      padding: media.padding,
    );
    final entry = _buildDialEntry(
      anchor: anchor,
      mode: _DialMode.persistent,
      direction: null,
    );
    _persistentEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() => _persistentPhase = LiquidPhase.opening);
    _startDialAnimation(onSettled: () {
      if (mounted && _persistentPhase == LiquidPhase.opening) {
        setState(() => _persistentPhase = LiquidPhase.open);
      }
    });
  }

  void _closePersistentDial() {
    if (!_dialOpen) return;
    setState(() => _persistentPhase = LiquidPhase.closing);
    final entry = _persistentEntry;
    _persistentEntry = null;
    if (entry != null) {
      _removeEntryWithReverse(entry, onDone: () {
        if (mounted && _persistentPhase == LiquidPhase.closing) {
          setState(() => _persistentPhase = LiquidPhase.closed);
        }
      });
    }
  }

  void _startDialAnimation({VoidCallback? onSettled}) {
    if (_reducedMotion) {
      _dial.value = 1.0;
      onSettled?.call();
    } else {
      _dial.forward(from: 0.0).whenCompleteOrCancel(() => onSettled?.call());
    }
  }

  /// Reverse the goo animation, then remove the entry — never a hard
  /// pop mid-flight (the goo would vanish, not melt).
  void _removeEntryWithReverse(OverlayEntry entry, {VoidCallback? onDone}) {
    if (_reducedMotion) {
      _dial.value = 0.0;
      entry.remove();
      onDone?.call();
      return;
    }
    _dial.reverse().whenCompleteOrCancel(() {
      entry.remove();
      onDone?.call();
    });
  }

  // ── ONE guarded execution path ────────────────────────────────────────────
  //
  // Shared verbatim by the transient gesture release, the persistent
  // dial's icon taps and the accessibility custom actions: availability
  // check, then EXACTLY one confirmation haptic, then the host's real
  // callback. No path can bypass a direction's existing confirmation
  // (show-less) or fire an unavailable delegate.
  void _executeDirection(ProfileJoystickDirection direction) {
    final action = widget.actions.actionFor(direction);
    if (action.onRelease == null) return; // unavailable: no dead fire
    AzamanHaptics.confirm();
    action.onRelease!();
  }

  /// Persistent-dial icon tap: close the dial, then execute exactly once.
  void _pickFromDial(ProfileJoystickDirection direction) {
    final action = widget.actions.actionFor(direction);
    if (action.onRelease == null) return; // dimmed icons never fire
    _closePersistentDial();
    _executeDirection(direction);
  }

  // ── Accessibility ─────────────────────────────────────────────────────────

  /// Every AVAILABLE direction is exposed as a custom semantics action
  /// with the host's honest, state-aware label, so an assistive-tech
  /// user who cannot perform the directional swipe can still invoke the
  /// exact same callbacks. Unavailable directions are OMITTED — never
  /// advertised, never executable. The 'open full action menu' action is
  /// ALWAYS exposed: it is the same real menu the hold gesture opens.
  Map<CustomSemanticsAction, VoidCallback> _accessibleActions() {
    final result = <CustomSemanticsAction, VoidCallback>{};
    for (final direction in ProfileJoystickDirection.values) {
      final action = widget.actions.actionFor(direction);
      if (!action.available) continue;
      final custom = CustomSemanticsAction(label: action.label);
      if (result.containsKey(custom)) continue;
      result[custom] = () {
        if (_dialOpen) _closePersistentDial();
        _executeDirection(direction);
      };
    }
    const openMenu = CustomSemanticsAction(label: 'Open full action menu');
    result[openMenu] = () {
      if (_dialOpen) _closePersistentDial();
      widget.onLongPress();
    };
    return result;
  }

  /// The avatar's REAL global rect — the dial anchors here, never on a
  /// guessed screen offset.
  Rect? _anchorRect() {
    final avatarContext = _avatarKey.currentContext;
    final render =
        avatarContext?.findRenderObject() ?? context.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    return render.localToGlobal(Offset.zero) & render.size;
  }

  @override
  void dispose() {
    // Route disposal / widget teardown: close WITHOUT performing an
    // action and never leak an overlay entry or a global route.
    _session = null;
    _uninstallGlobalRoute();
    _persistentEntry?.remove();
    _persistentEntry = null;
    _dial.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _session != null;
    return Semantics(
      // The tap action toggles the persistent dial open/closed.
      button: true,
      onTap: _dialOpen ? _closePersistentDial : _openPersistentDial,
      expanded: _dialOpen,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      customSemanticsActions: _accessibleActions(),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _JoystickGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_JoystickGestureRecognizer>(
                () => _JoystickGestureRecognizer(
                  debugOwner: this,
                  activationSlop: widget.activationSlop,
                  axisSwitchMargin: _axisSwitchMargin,
                  longPressTimeout: kLongPressTimeout,
                ),
                (recogniser) {
                  recogniser
                    ..onTrackingStart = _sessionStart
                    ..onDragStarted = _sessionDragStarted
                    ..onDirectionChanged = _sessionDirectionChanged
                    ..onReleased = _sessionReleased
                    ..onLongPressed = _sessionLongPressed
                    ..onCancelled = _sessionCancelled;
                },
              ),
        },
        child: AnimatedScale(
          scale: active ? 0.96 : 1.0,
          duration: _reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 110),
          child: KeyedSubtree(key: _avatarKey, child: widget.child),
        ),
      ),
    );
  }

  // ── The dial overlay ─────────────────────────────────────────────────────

  OverlayEntry _buildDialEntry({
    required Rect anchor,
    required _DialMode mode,
    required ProfileJoystickDirection? direction,
  }) {
    final geometry = mode == _DialMode.persistent
        ? _persistentGeometry!
        : ProfileDialGeometry.solve(
            anchor: anchor,
            screen: MediaQuery.of(context).size,
            padding: MediaQuery.of(context).padding,
          );
    final colors = ref.read(themeProvider).colors;
    final dir = Directionality.of(context);
    final reduced = _reducedMotion;

    return OverlayEntry(
      builder: (_) => Directionality(
        textDirection: dir,
        child: _ProfileDialOverlay(
          controller: _dial,
          anchor: anchor,
          geometry: geometry,
          actions: widget.actions,
          mode: mode,
          direction: direction,
          colors: colors,
          reduced: reduced,
          // Transient highlight follows the LIVE session direction
          // (the entry is markNeedsBuild-ed on every change).
          liveDirection: mode == _DialMode.transient
              ? () => _session?.direction
              : null,
          onDismiss: mode == _DialMode.persistent ? _closePersistentDial : null,
          onPick: mode == _DialMode.persistent ? _pickFromDial : null,
        ),
      ),
    );
  }
}

/// Live session bookkeeping. [cancelled] marks a session that must NOT
/// fire on the (still-incoming) release of its original pointer.
class _Session {
  _Session({required this.phase});
  ProfileSessionPhase phase;
  ProfileJoystickDirection? direction;
  bool cancelled = false;
  OverlayEntry? entry;
}

enum _DialMode { transient, persistent }

// ── The dial overlay widget ────────────────────────────────────────────────

/// The liquid dial: goo body + four icon-only circular buttons around
/// the anchored avatar, riding the ROOT overlay so satellites may extend
/// outside the card without being clipped.
///
/// TRANSIENT mode (gesture): no barrier, satellites display-only
/// (IgnorePointer + ExcludeSemantics — selection is by movement, so no
/// satellite can be tapped into a second action, and the open dial adds
/// no duplicate screen-reader stops).
///
/// PERSISTENT mode (tap): a full-screen dismissal barrier owns every
/// interaction (tapping outside closes SILENTLY — nothing beneath fires
/// and the feed never scrolls); satellites are tappable semantic buttons;
/// tapping the anchor area closes the dial.
class _ProfileDialOverlay extends StatelessWidget {
  const _ProfileDialOverlay({
    required this.controller,
    required this.anchor,
    required this.geometry,
    required this.actions,
    required this.mode,
    required this.direction,
    required this.colors,
    required this.reduced,
    this.liveDirection,
    this.onDismiss,
    this.onPick,
  });

  final AnimationController controller;
  final Rect anchor;
  final ProfileDialGeometry geometry;
  final ProfileJoystickActions actions;
  final _DialMode mode;
  final ProfileJoystickDirection? direction;
  final AzamanColors colors;

  final bool reduced;
  final VoidCallback? onDismiss;
  final void Function(ProfileJoystickDirection)? onPick;

  /// The LIVE selected direction for transient mode (the entry is
  /// rebuilt by markNeedsBuild on every direction CHANGE, and reads the
  /// session through this getter — a captured value could never
  /// highlight after the entry was built).
  final ProfileJoystickDirection? Function()? liveDirection;

  @override
  Widget build(BuildContext context) {
    final persistent = mode == _DialMode.persistent;

    // Everything visible animates with the controller: the goo painter
    // AND the satellites' launch (travel/scale/opacity). A satellite
    // built once at insertion would sit collapsed at the anchor with
    // its reveal gate absorbing every tap.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = liveDirection?.call() ?? direction;
        return Stack(
          key: const ValueKey('profile-dial'),
          children: _buildChildren(context, persistent, selected),
        );
      },
    );
  }

  List<Widget> _buildChildren(
    BuildContext context,
    bool persistent,
    ProfileJoystickDirection? selected,
  ) {
    final bounds = geometry.bounds(anchor);
    final children = <Widget>[
      // 1. Dismissal barrier — persistent mode only. Opaque hit-test
      //    swallows the tap (and any drag: the feed below never
      //    receives it) and closes the dial SILENTLY.
      if (persistent)
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              key: const ValueKey('profile-dial-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      // 2. The goo body — one layer painting anchor ring + necks +
      //    satellite bulges with the shared category-dial treatment.
      Positioned.fromRect(
        rect: bounds,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: controller,
                builder: (_, __) => CustomPaint(
                  painter: DialGooPainter(
                    t: reduced ? 1 : controller.value,
                    origin: bounds.topLeft,
                    anchor: anchor,
                    slots: geometry.slots(),
                    body: kDialGooBody,
                    rim: kDialGooRim,
                    // Circle grammar: the anchor is the photo itself
                    // (painted as a RING so it stays visible) and the
                    // satellites are compact circular bulges.
                    anchorRadius: anchor.shortestSide / 2,
                    satelliteRadius: kProfileDialVisualSize / 2,
                    neckBaseRadius: kProfileDialVisualSize * 0.30,
                    anchorAsRing: true,
                    neckStartRadius: anchor.shortestSide / 2 - 4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // 3. The anchor dismiss zone — persistent mode: tapping the
      //    photo itself dismisses the dial. A central 44×44 zone, BELOW
      //    the satellites: the goo merge intentionally overlaps each
      //    satellite's visual with the photo rim, and that overlap
      //    belongs to the SATELLITE's 44×44 target, never to the anchor
      //    (a stolen strip would shrink a target below the minimum).
      //    Pure hit zone (transparent): the REAL avatar beneath the
      //    overlay stays the visible anchor, and its semantics node
      //    (tap = toggle) is the single screen-reader stop here.
      if (persistent)
        Positioned.fromRect(
          rect: Rect.fromCenter(
            center: anchor.center,
            width: kProfileDialHitSize,
            height: kProfileDialHitSize,
          ),
          child: GestureDetector(
            key: const ValueKey('profile-dial-anchor'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ExcludeSemantics(child: SizedBox.expand()),
          ),
        ),
      // 4. The four icon-only satellites — topmost interactive layer.
      for (final d in ProfileJoystickDirection.values)
        _DialSatellite(
          controller: controller,
          geometry: geometry,
          direction: d,
          action: actions.actionFor(d),
          selected: selected == d,
          colors: colors,
          reduced: reduced,
          persistent: persistent,
          onPick: onPick,
        ),
    ];
    if (!persistent) {
      // Transient mode: display-only. The whole overlay (barrier,
      // satellites, goo) is rebuilt per tick but stays non-interactive —
      // selection is by movement only.
      return <Widget>[
        ExcludeSemantics(
          child: IgnorePointer(
            child: Stack(children: children),
          ),
        ),
      ];
    }
    return children;
  }
}

/// One icon-only circular satellite: ≥44×44 tappable target (persistent
/// mode), 40dp visual circle, crisp icon on top of the goo, honest
/// disabled treatment for unavailable directions.
class _DialSatellite extends StatelessWidget {
  const _DialSatellite({
    required this.controller,
    required this.geometry,
    required this.direction,
    required this.action,
    required this.selected,
    required this.colors,
    required this.reduced,
    required this.persistent,
    required this.onPick,
  });

  final AnimationController controller;
  final ProfileDialGeometry geometry;
  final ProfileJoystickDirection direction;
  final ProfileJoystickAction action;
  final bool selected;
  final AzamanColors colors;
  final bool reduced;
  final bool persistent;
  final void Function(ProfileJoystickDirection)? onPick;

  @override
  Widget build(BuildContext context) {
    final hit = geometry.hitRects[direction]!;
    final t = reduced ? 1.0 : controller.value;
    final travel = satelliteTravel(t, direction.index);
    final scale = satelliteScale(t, direction.index);
    // Satellites fly OUT from the anchor (the photo) while the goo
    // opens — the same launch grammar as the category dial.
    final from = geometry.anchorCenter;
    final pos = Rect.fromLTWH(
      from.dx + (hit.left - from.dx) * travel,
      from.dy + (hit.top - from.dy) * travel,
      hit.width,
      hit.height,
    );
    final visual = Container(
      width: kProfileDialVisualSize,
      height: kProfileDialVisualSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.card,
        border: Border.all(
          color: selected ? colors.accent : colors.divider,
          width: selected ? 1.6 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        action.icon,
        size: _kDialIconSize,
        color: action.available
            ? (selected ? colors.accent : colors.textPrimary)
            : colors.textTertiary,
      ),
    );

    final dimmed = !action.available;
    final button = Semantics(
      button: true,
      enabled: action.available,
      // Icon-only is a VISUAL rule: the label (and the honest
      // unavailable state) stays for assistive technology.
      label: action.available
          ? action.label
          : '${action.label} (${action.unavailableLabel})',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: dimmed || !persistent ? null : () => onPick?.call(direction),
        child: Container(
          width: kProfileDialHitSize,
          height: kProfileDialHitSize,
          alignment: Alignment.center,
          child: Opacity(
            opacity: dimmed ? 0.45 : (selected ? 1.0 : 0.9),
            child: Transform.scale(
              scaleX: scale.sx,
              scaleY: scale.sy,
              child: visual,
            ),
          ),
        ),
      ),
    );

    return Positioned.fromRect(
      key: ValueKey('profile-dial-satellite-${direction.name}'),
      rect: pos,
      child: LiquidReveal(
        // Nothing is tappable before it is readable.
        opacity: ((travel - 0.25) / 0.35).clamp(0.0, 1.0),
        child: button,
      ),
    );
  }
}

// ── The recogniser ──────────────────────────────────────────────────────────

/// An arena-participating one-pointer recogniser implementing the
/// explicit three-outcome state machine:
///
///   * pointer down          → reports tracking start (pressing).
///   * FIRST displacement >= [activationSlop] → reports the drag
///     outcome (the transient dial opens; the arena was already won
///     at pointer-down).
///   * [longPressTimeout] elapses while still pressing (no slop
///     crossing) → accepts, reports the hold outcome, and CONSUMES the
///     pointer: its eventual release reports nothing.
///   * pointer up while pressing (no slop, no hold) → accepts (wins the
///     sweep deterministically) and reports the TAP outcome (persistent
///     dial).
///   * pointer up while dragging → reports the release with the live
///     classified direction — the ONE place a direction may fire.
///   * pointer up after the hold → reports nothing (consumed).
///   * cancel / rejected → reports cancellation — no outcome.
class _JoystickGestureRecognizer extends OneSequenceGestureRecognizer {
  _JoystickGestureRecognizer({
    required super.debugOwner,
    this.activationSlop = 16.0,
    this.axisSwitchMargin = 4.0,
    this.longPressTimeout = const Duration(milliseconds: 500),
  });

  /// Spec range 14-20 logical px.
  final double activationSlop;

  /// Required dominance margin before the dominant axis may flip.
  final double axisSwitchMargin;

  /// Platform-appropriate hold time (Material kLongPressTimeout).
  final Duration longPressTimeout;

  // Rewired on every build by the factory handler.
  void Function(int pointer)? onTrackingStart;
  VoidCallback? onDragStarted;
  void Function(ProfileJoystickDirection? direction)? onDirectionChanged;
  void Function(ProfileJoystickDirection? direction)? onReleased;
  VoidCallback? onLongPressed;
  VoidCallback? onCancelled;

  int? _pointer;
  Offset _down = Offset.zero;
  bool _accepted = false;
  bool _dragging = false;
  bool _consumed = false;
  ProfileJoystickDirection? _direction;
  Timer? _longPressTimer;

  @override
  bool isPointerAllowed(PointerEvent event) => _pointer == null;

  void _startLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(longPressTimeout, _onLongPressTimeout);
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onLongPressTimeout() {
    if (_pointer == null || _dragging || _consumed) return;
    // The hold wins: own the pointer for the rest of the sequence and
    // consume it — the eventual release must produce nothing.
    _consumed = true;
    resolve(GestureDisposition.accepted);
    onLongPressed?.call();
  }

  @override
  void addAllowedPointer(PointerEvent event) {
    if (_pointer != null) return; // single-pointer contract
    startTrackingPointer(event.pointer);
    _pointer = event.pointer;
    _down = event.position;
    _accepted = false;
    _dragging = false;
    _consumed = false;
    _direction = null;
    onTrackingStart?.call(event.pointer);
    _startLongPressTimer();
    // The profile owns EVERY pointer that begins on it: the arena is
    // won at pointer-DOWN, deterministically, before the parent
    // scroll's 18px touch slop (or any horizontal shell swipe) could
    // ever claim it — a profile-started gesture NEVER scrolls the
    // feed. WHICH outcome runs is decided later by the state machine;
    // ownership itself is not negotiable.
    resolve(GestureDisposition.accepted);
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
      // single-axis slippage on diagonals). The hold timer is dead from
      // here on — this pointer sequence can no longer become a hold.
      _accepted = true;
      _dragging = true;
      _cancelLongPressTimer();
      resolve(GestureDisposition.accepted);
      onDragStarted?.call();
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
        raw == ProfileJoystickDirection.menu || raw == ProfileJoystickDirection.story;
    final currentVertical = current == ProfileJoystickDirection.menu ||
        current == ProfileJoystickDirection.story;
    if (rawVertical == currentVertical) return raw; // same axis: follow
    // Axis flip only with clear dominance (hysteresis vs tremor).
    final dominant = rawVertical ? delta.dy.abs() : delta.dx.abs();
    final other = rawVertical ? delta.dx.abs() : delta.dy.abs();
    return dominant > other + axisSwitchMargin ? raw : current;
  }

  void _handleUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    final direction = _direction;
    final wasAccepted = _accepted;
    final consumed = _consumed;
    if (!wasAccepted && !consumed) {
      // Plain tap: accept so WE win the sweep deterministically.
      resolve(GestureDisposition.accepted);
    }
    stopTrackingPointer(event.pointer);
    _reset();
    if (consumed) return; // the hold already fired; release is silent
    onReleased?.call(wasAccepted ? direction : null);
  }

  void _handleCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
    if (!_accepted && !_consumed) {
      resolve(GestureDisposition.rejected);
    }
    stopTrackingPointer(event.pointer);
    _reset();
    onCancelled?.call();
  }

  void _reset() {
    _pointer = null;
    _accepted = false;
    _dragging = false;
    _consumed = false;
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
    _cancelLongPressTimer();
    _reset();
    super.dispose();
  }
}
