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
class QuietDepthController extends ChangeNotifier {
  QuietDepthController({
    this.idleDelay = const Duration(milliseconds: 2700),
  });

  /// How long the controls stay raised after entry / a wake before they
  /// settle into the quiet state.
  final Duration idleDelay;

  QuietDepthState _depth = QuietDepthState.raised;
  Timer? _idleTimer;
  _QuietFocusRegion? _focus;
  bool _disposed = false;

  /// What registered surfaces render: recessed while any focal region is
  /// active, otherwise the settled idle state.
  QuietDepthState get depth =>
      _focus != null ? QuietDepthState.recessed : _depth;

  /// The id of the active focal region, if any.
  String? get focusId => _focus?.id;

  /// True while the user is inside a designated focal region.
  bool get isFocused => _focus != null;

  /// A qualifying interaction wakes the controls: raise them and restart
  /// the idle cycle. While a focal region is active this is a no-op — the
  /// region system owns elevation during focus, so a stray pointer event
  /// can never cancel a focus state out from under the user.
  void wake() {
    if (_disposed || _focus != null) return;
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
    if (_focus?.id == id) return;
    _focus = _QuietFocusRegion(
      id: id,
      exitOnOutsideTap: exitOnOutsideTap,
      context: context ?? _focus?.context,
    );
    _idleTimer?.cancel();
    _idleTimer = null;
    notifyListeners();
  }

  /// The focal region releases the stage: controls rise and the idle cycle
  /// restarts. Only the ACTIVE region can release; stale exits are ignored.
  void exitFocus(String id) {
    if (_disposed || _focus?.id != id) return;
    _focus = null;
    _depth = QuietDepthState.raised;
    _restartIdle();
    notifyListeners();
  }

  /// Root pointer handler (translucent — gestures are untouched). A tap
  /// OUTSIDE the active focal region releases focus; taps inside are the
  /// region's own business.
  void handlePointerDown(Offset globalPosition) {
    final focus = _focus;
    if (focus == null || !focus.exitOnOutsideTap) return;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) {
      exitFocus(focus.id);
      return;
    }
    final box = ctx.findRenderObject();
    if (box is! RenderBox) {
      exitFocus(focus.id);
      return;
    }
    final local = box.globalToLocal(globalPosition);
    if (!box.size.contains(local)) {
      exitFocus(focus.id);
    }
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDelay, () {
      if (_disposed || _focus != null) return;
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

/// The [InheritedWidget] that exposes the controller down the subtree.
class _QuietDepthInherited extends InheritedNotifier<QuietDepthController> {
  const _QuietDepthInherited({
    required super.notifier,
    required super.child,
  });

  static QuietDepthController? maybeOf(BuildContext context) =>
      context
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

  static QuietDepthController of(BuildContext context) =>
      maybeOf(context)!;

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
        onPointerDown: (d) => _controller.handlePointerDown(
          d.position,
        ),
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
    if (old.active != widget.active ||
        old.regionId != widget.regionId) {
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

/// An opt-in quiet-depth surface: builds a raised and a recessed backdrop
/// around the SAME content and cross-fades between them when the scoped
/// depth changes. Content (icon, label, hit target, semantics) is never
/// scaled, moved or hidden — only the backdrop decoration animates.
class QuietDepthSurface extends ConsumerWidget {
  const QuietDepthSurface({
    super.key,
    required this.builder,
  });

  /// Builds the full surface for the given depth state. Both variants
  /// must share identical geometry.
  final Widget Function(BuildContext context, bool recessed) builder;

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

    return AnimatedSwitcher(
      duration: duration,
      // No scale/slide — a pure depth cross-fade. Both children occupy
      // the same box, so the hit target never moves.
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
      // Named keys: the switcher swaps on them AND tests/captures can
      // pin which depth state is mounted.
      child: KeyedSubtree(
        key: ValueKey<String>(
          recessed ? 'quiet-depth-recessed' : 'quiet-depth-raised',
        ),
        child: builder(context, recessed),
      ),
    );
  }
}
