// =============================================================================
// AZVERTICAL ACCENT SCOPE  (TASK-025 — §G.6)
//
// A Marketplace vertical borrows an accent for the duration of its route:
// being inside Restaurants can look different from being inside Hotels
// without the user managing another theme.
//
// Design notes:
//   • The override lives in a top-level session-only StateProvider because
//     the SHELL (MaterialApp theme, above the router) must see it — a
//     ProviderScope override on the subtree would be invisible to the app
//     theme above.
//   • The scope mutates the provider in a MICROTASK, after the current
//     frame returns. Writing during build or the draw phase throws
//     ("modifying provider while the widget tree is building"), and even
//     post-frame callbacks still run inside the frame's persistent-callbacks
//     phase, which trips the same riverpod guard. A microtask fires as soon
//     as the frame's synchronous work ends — before the next frame — so the
//     shell still sees the override on the very next paint.
//   • Leaving the route clears the override so the user's saved identity
//     (ThemeProvider._accent) is restored automatically. The vertical
//     accent is NEVER persisted and never mutates ThemeProvider._accent.
// =============================================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';

/// Session-only vertical accent override. `null` = no vertical active —
/// the shell resolves the user's saved identity instead.
final verticalAccentProvider = StateProvider<AzAccent?>((ref) => null);

/// Wraps a Marketplace vertical route. While mounted, the shell resolves the
/// theme through [accent]; when the route leaves the tree the override is
/// cleared and the user's saved identity returns.
///
/// Implemented as a [ConsumerStatefulWidget] rather than the plain
/// ConsumerWidget sketch in the brief: the clear-on-leave behaviour requires
/// a dispose-phase hook, and `ref` is unsafe inside `State.dispose`. The
/// cleanup therefore runs in `deactivate` — the last lifecycle point where
/// the element is still mounted and `ref` is still legal.
class AzVerticalAccentScope extends ConsumerStatefulWidget {
  final AzAccent accent;
  final Widget child;

  const AzVerticalAccentScope({
    super.key,
    required this.accent,
    required this.child,
  });

  @override
  ConsumerState<AzVerticalAccentScope> createState() =>
      _AzVerticalAccentScopeState();
}

class _AzVerticalAccentScopeState extends ConsumerState<AzVerticalAccentScope> {
  @override
  void initState() {
    super.initState();
    _schedule(widget.accent);
  }

  @override
  void deactivate() {
    // The scope is leaving the tree (route popped). Capture the session
    // controller NOW — the element is still mounted so `ref` is legal —
    // and flip it back in the microtask queue, after the frame.
    _schedule(null);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply after a deactivate/reactivate cycle (e.g. reparenting): the
    // override must reflect the live scope again even though initState
    // will not re-run. deactivate's clear was queued first, so the queue
    // order (clear, then re-apply) leaves the live scope owning the state.
    if (ref.watch(verticalAccentProvider) != widget.accent) {
      _schedule(widget.accent);
    }
    return widget.child;
  }

  /// Queues a session-override write for the microtask that follows the
  /// current frame. Reading a provider inside a lifecycle hook is safe; it
  /// is the WRITE that riverpod forbids during build/draw, so the captured
  /// controller is flipped after the frame's synchronous work ends —
  /// still before any next frame can paint.
  void _schedule(AzAccent? accent) {
    final controller = ref.read(verticalAccentProvider.notifier);
    scheduleMicrotask(() {
      if (accent == null) {
        // Only clear what WE applied — another live scope (or a newer
        // route) may have taken ownership since this one was queued.
        if (controller.state == widget.accent) controller.state = null;
      } else if (controller.state != accent) {
        controller.state = accent;
      }
    });
  }
}

/// The accent-aware palette the shell should render with: the vertical's
/// session accent while a vertical is active, otherwise the user's saved
/// identity. Static [ThemeProvider.getColors] is the historical baseline;
/// this provider is the resolved "what should the app look like right now".
final resolvedAzamanColorsProvider = Provider<AzamanColors>((ref) {
  final theme = ref.watch(themeProvider);
  final vertical = ref.watch(verticalAccentProvider);
  final base = ThemeProvider.getColors(theme.currentTheme);
  return base.withAccent(vertical ?? theme.accent);
});
