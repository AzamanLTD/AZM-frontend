// =============================================================================
// AZAMAN — QUIET DEPTH (scoped focus/depth system, Home pilot 2026-10-22)
//
// The owner's concept: raised tactile controls settle into a nearly flush
// "quiet" state after an idle moment, and the UI uses DEPTH to communicate
// focus. While a designated FOCAL surface holds the user's attention, the
// secondary controls recess so the focal surface keeps the visual stage.
//
// DESIGN RULES (from the pilot brief):
//   • Scoped, opt-in, isolated from navigation and business logic. A scope
//     wraps a region subtree; only surfaces that opt in via
//     [QuietDepthSurface] react. Nothing else changes.
//   • Region-aware: a focal region REGISTERS itself; a qualifying
//     interaction outside the focused region releases focus. There is NO
//     global "raise on every pointer event" rule — only region-tagged
//     exits and explicit [wake]s.
//   • Idle settle is separate from the transition duration: the controls
//     sit raised for [idleDelay] (~2.5–3s) and then cross-fade into the
//     recessed recipe over [transitionDuration] (~160–200ms).
//   • Reduced motion: the state change is immediate (the visual fade
//     collapses to zero); the recessed/raised states stay DISTINCT, so
//     animation is never the only cue.
//   • Touch is never held up: the depth state is pure decoration; every
//     action runs on its own recognisers at full speed.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// The two depth states a registered surface can render.
enum QuietDepthState { raised, recessed }

/// One registered focal region.
@immutable
class _QuietFocusRegion {
  const _QuietFocusRegion({
    required this.id,
    required this.exitOnOutsideTap,
    required this.context,
  });
  final String id;
  final bool exitOnOutsideTap;
  final BuildContext? context;
}

/// The scoped controller. Owned by [QuietDepthScope]; reachable by anything
/// below it via [QuietDepthScope.of] / [QuietDepthScope.maybeOf].
///
/// State machine:
///   raised --idle timer--> recessed          (no focus active)
///   wake()  --> raised + restart the idle timer (no-op while focused)
///   enterFocus(id) --> focus held; controls forced recessed; idle cancelled
///   exitFocus(id)  --> raised + restart the idle timer
///
/// Wake arbitration: designated focal surfaces (see
/// [registerFocalSurface]) publish their hit bounds to the scope. A
/// pointer-down INSIDE one of them is the surface's own gesture, not an
/// ordinary page touch — the scope does NOT wake the secondary controls
/// for it, so a focal swipe that is still crossing the recognizer's
/// slop can never flash the pills raised before its own focus claim.
class QuietDepthController extends ChangeNotifier {
  QuietDepthController({this.idleDelay = const Duration(milliseconds: 2700)});

  /// How long the controls stay raised after entry / a wake before they
  /// settle into the quiet state.
  final Duration idleDelay;

  QuietDepthState _depth = QuietDepthState.raised;
  Timer? _idleTimer;
  final Map<String, _QuietFocusRegion> _focusRegions = {};

  /// Designated focal surfaces, by id: their hit bounds only, never
  /// state. Registration is geometry for wake arbitration — a surface
  /// being registered does NOT make it active (that is [enterFocus]).
  final Map<String, BuildContext> _focalSurfaces = {};
  bool _disposed = false;

  /// What registered surfaces render: recessed while ANY focal region is
  /// active, otherwise the settled idle state.
  QuietDepthState get depth =>
      _focusRegions.isNotEmpty ? QuietDepthState.recessed : _depth;

  /// The id of the most recently entered focal region, if any.
  String? get focusId => _focusRegions.isEmpty ? null : _focusRegions.keys.last;

  /// True while the user is inside at least one designated focal region.
  bool get isFocused => _focusRegions.isNotEmpty;

  /// The registered focal region ids, in entry order.
  List<String> get activeFocusIds => List.unmodifiable(_focusRegions.keys);

  /// A qualifying interaction wakes the controls: raise them and restart
  /// the idle cycle. While a focal region is active this is a no-op — the
  /// region system owns elevation during focus, so a stray pointer event
  /// can never cancel a focus state out from under the user.
  void wake() {
    if (_disposed || _focusRegions.isNotEmpty) return;
    _depth = QuietDepthState.raised;
    _restartIdle();
    notifyListeners();
  }

  /// A focal region takes the stage: secondary controls recess and the
  /// idle timer stops. Idempotent per region id.
  void enterFocus(
    String id, {
    BuildContext? context,
    bool exitOnOutsideTap = false,
  }) {
    if (_disposed) return;
    final existing = _focusRegions[id];
    if (existing != null) {
      // Already active: refresh the registration context only. Concurrent
      // regions NEVER evict each other — the map holds them all.
      if (context == null || identical(existing.context, context)) return;
      _focusRegions[id] = _QuietFocusRegion(
        id: id,
        exitOnOutsideTap: exitOnOutsideTap,
        context: context,
      );
      notifyListeners();
      return;
    }
    _focusRegions[id] = _QuietFocusRegion(
      id: id,
      exitOnOutsideTap: exitOnOutsideTap,
      context: context,
    );
    _idleTimer?.cancel();
    _idleTimer = null;
    notifyListeners();
  }

  /// The focal region releases the stage. Only regions that are actually
  /// active can release, and releasing one never disturbs the others —
  /// the controls rise only when the LAST active region is gone.
  void exitFocus(String id) {
    if (_disposed || !_focusRegions.containsKey(id)) return;
    _focusRegions.remove(id);
    if (_focusRegions.isEmpty) {
      _depth = QuietDepthState.raised;
      _restartIdle();
    }
    notifyListeners();
  }

  /// A designated focal surface (reminder deck, wallet deck) publishes
  /// its hit bounds so [handlePointerDown] can tell its own gestures
  /// apart from ordinary page touches BEFORE any recognizer has claimed
  /// the gesture. Idempotent per id; re-registering refreshes geometry.
  void registerFocalSurface(String id, {required BuildContext context}) {
    if (_disposed) return;
    _focalSurfaces[id] = context;
  }

  /// The surface left the tree. Silent about unknown ids.
  void unregisterFocalSurface(String id) {
    _focalSurfaces.remove(id);
  }

  /// Whether [globalPosition] is inside any registered focal surface.
  /// Unmounted contexts are dropped on the fly, so a stale registration
  /// can never suppress a wake that should happen.
  bool _touchOnFocalSurface(Offset globalPosition) {
    for (final id in List.of(_focalSurfaces.keys)) {
      final ctx = _focalSurfaces[id];
      if (ctx == null || !ctx.mounted) {
        _focalSurfaces.remove(id);
        continue;
      }
      final box = ctx.findRenderObject();
      if (box is RenderBox &&
          box.size.contains(box.globalToLocal(globalPosition))) {
        return true;
      }
    }
    return false;
  }

  /// Root pointer handler (translucent — gestures are untouched).
  ///
  /// • While a focal region with [exitOnOutsideTap] is active, a tap
  ///   OUTSIDE that region releases IT (other regions keep the stage).
  /// • While NO focal region is active, ordinary pointer activity wakes
  ///   the settled controls and restarts the idle cycle — touch and
  ///   scroll across the whole scope raise them again.
  /// • EXCEPT a down that lands inside a designated focal surface: that
  ///   touch belongs to the surface (its own recognizers claim focus if
  ///   it becomes a gesture), so the scope stays quiet and the secondary
  ///   controls never flash raised during slop recognition.
  void handlePointerDown(Offset globalPosition) {
    if (_disposed) return;
    var released = false;
    for (final region in List.of(_focusRegions.values)) {
      if (!region.exitOnOutsideTap) continue;
      final ctx = region.context;
      var outside = true;
      if (ctx != null && ctx.mounted) {
        final box = ctx.findRenderObject();
        if (box is RenderBox) {
          outside = !box.size.contains(box.globalToLocal(globalPosition));
        }
      }
      if (outside) {
        exitFocus(region.id);
        released = true;
      }
    }
    // No focal region involved in this touch. An ordinary page touch
    // wakes the settled controls; a touch on a designated focal surface
    // does not — that gesture is the surface's to claim, and waking now
    // would flash the controls raised mid-recognition, only to reverse
    // when the surface's focus claim lands.
    if (!released &&
        _focusRegions.isEmpty &&
        !_touchOnFocalSurface(globalPosition)) {
      wake();
    }
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDelay, () {
      if (_disposed || _focusRegions.isNotEmpty) return;
      _depth = QuietDepthState.recessed;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _disposed = true;
    super.dispose();
  }
}

/// Marks its subtree as a DESIGNATED FOCAL SURFACE for wake
/// arbitration. A pointer-down that lands inside [child] never wakes
/// the secondary controls: the surface's own recognizers own the
/// gesture, and a real interaction claims focus via the scope's
/// enterFocus — so a swipe that is still crossing the recognizer's slop
/// can never flash the controls raised mid-recognition.
///
/// Registration is GEOMETRY ONLY (hit bounds for pointer-down
/// arbitration), never state: wrapping a subtree does not make it
/// focused, and focus never depends on it. Ordinary touches and scrolls
/// elsewhere in the scope keep waking the controls exactly as before.
class QuietDepthFocalSurface extends StatefulWidget {
  const QuietDepthFocalSurface({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  State<QuietDepthFocalSurface> createState() => _QuietDepthFocalSurfaceState();
}

class _QuietDepthFocalSurfaceState extends State<QuietDepthFocalSurface> {
  QuietDepthController? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final quiet = QuietDepthScope.maybeOf(context);
    if (quiet != _scope) {
      _scope?.unregisterFocalSurface(widget.id);
      _scope = quiet;
    }
    quiet?.registerFocalSurface(widget.id, context: context);
  }

  @override
  void dispose() {
    _scope?.unregisterFocalSurface(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The [InheritedWidget] that exposes the controller down the subtree.
class _QuietDepthInherited extends InheritedNotifier<QuietDepthController> {
  const _QuietDepthInherited({required super.notifier, required super.child});

  static QuietDepthController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_QuietDepthInherited>()
      ?.notifier;
}

/// Wraps a region subtree with the quiet-depth system. One scope per
/// surface (the Home pilot uses one); controls opt in individually with
/// [QuietDepthSurface]; focal regions register with [QuietDepthRegion] or
/// via the controller's enter/exitFocus pair.
class QuietDepthScope extends StatefulWidget {
  const QuietDepthScope({
    super.key,
    required this.child,
    this.idleDelay = const Duration(milliseconds: 2700),
  });

  final Widget child;

  /// Overridable for tests; production uses the tuned default.
  final Duration idleDelay;

  static QuietDepthController? maybeOf(BuildContext context) =>
      _QuietDepthInherited.maybeOf(context);

  static QuietDepthController of(BuildContext context) => maybeOf(context)!;

  @override
  State<QuietDepthScope> createState() => _QuietDepthScopeState();
}

class _QuietDepthScopeState extends State<QuietDepthScope> {
  late final QuietDepthController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuietDepthController(idleDelay: widget.idleDelay)
      .._restartIdle();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _QuietDepthInherited(
      notifier: _controller,
      child: Listener(
        // Translucent: every child recogniser still wins its own gestures;
        // the scope only OBSERVES pointer-downs for the outside-tap rule.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (d) => _controller.handlePointerDown(d.position),
        child: widget.child,
      ),
    );
  }
}

/// Registers a subtree as a focal region. While it holds focus, secondary
/// controls recess. With [exitOnOutsideTap] the scope releases focus when a
/// pointer lands outside this subtree (the reminder-deck rule).
class QuietDepthRegion extends StatefulWidget {
  const QuietDepthRegion({
    super.key,
    required this.regionId,
    required this.child,
    this.exitOnOutsideTap = false,
    this.active = true,
  });

  final String regionId;
  final Widget child;
  final bool exitOnOutsideTap;

  /// Whether the region currently CLAIMS focus (wired by the host to its
  /// own state; false keeps the region registered but passive).
  final bool active;

  @override
  State<QuietDepthRegion> createState() => _QuietDepthRegionState();
}

class _QuietDepthRegionState extends State<QuietDepthRegion> {
  QuietDepthController? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = QuietDepthScope.maybeOf(context);
    if (!identical(scope, _scope)) {
      _unregister();
      _scope = scope;
    }
    _register();
  }

  void _register() {
    if (widget.active) {
      _scope?.enterFocus(
        widget.regionId,
        context: context,
        exitOnOutsideTap: widget.exitOnOutsideTap,
      );
    } else {
      _scope?.exitFocus(widget.regionId);
    }
  }

  void _unregister() {
    _scope?.exitFocus(widget.regionId);
  }

  @override
  void didUpdateWidget(QuietDepthRegion old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.regionId != widget.regionId) {
      _unregister();
      _register();
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// An opt-in quiet-depth surface.
///
/// The surface is split in two layers:
/// • [content] — icon, label, semantics, hit target. Mounted EXACTLY
///   ONCE, above the backdrop, never scaled, moved, faded or duplicated
///   (assistive tech sees one control, also mid-transition).
/// • [backdrop] — the decorative depth recipe. This is the ONLY thing
///   that cross-fades between raised and recessed.
///
/// The stack is sized by the content, so both backdrop variants occupy
/// the same box and the hit target never moves.
class QuietDepthSurface extends ConsumerWidget {
  const QuietDepthSurface({
    super.key,
    required this.content,
    required this.backdrop,
  });

  /// The stable, interactive subtree. Sits ON TOP of the backdrop.
  final Widget content;

  /// Builds the decorative backdrop for the given depth state. It must
  /// fill the surface (wrap in [Positioned.fill]/[SizedBox.expand] as
  /// needed) and stay pointer-transparent or let the content win.
  final Widget Function(BuildContext context, bool recessed) backdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The theme watch keeps the backdrops in the right palette when the
    // theme flips mid-life.
    ref.watch(themeProvider.select((t) => t.currentTheme));

    final depth =
        QuietDepthScope.maybeOf(context)?.depth ?? QuietDepthState.raised;
    final recessed = depth == QuietDepthState.recessed;
    final duration = MotionTokens.accessibleDuration(
      context,
      const Duration(milliseconds: 180),
    );

    return Stack(
      children: [
        Positioned.fill(
          // Only the DECORATIVE layer is switched: the content subtree
          // is mounted once, above this point.
          child: AnimatedSwitcher(
            duration: duration,
            // No scale/slide — a pure depth cross-fade. Both variants
            // occupy the same box, so the backdrop never shifts geometry.
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.center,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            // Named keys: the switcher swaps on them AND tests/captures
            // can pin which depth state is mounted.
            child: KeyedSubtree(
              key: ValueKey<String>(
                recessed ? 'quiet-depth-recessed' : 'quiet-depth-raised',
              ),
              child: backdrop(context, recessed),
            ),
          ),
        ),
        // Sizing child: determines the stack's size, painted on top.
        content,
      ],
    );
  }
}
