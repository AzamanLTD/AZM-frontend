// AZAMAN — BUBBLE → SCREEN MORPH
//
// The Home bubbles are physical objects: small glass spheres you press. This
// file makes the press CONTINUE — the sphere's own material expands out of the
// row and becomes the service page, and back reverses it into the same sphere
// at the same place.
//
// How, and why this way:
//   • It is a Hero flight, not a custom router. The canonical GoRouter location
//     is still pushed (`/bills`, `/savings`, `/marketplace`, `/susu/...`), so
//     deep links, notifications and the back stack behave exactly as before.
//     Hero simply animates BETWEEN two heroes when both are on screen.
//   • When there is no source bubble (a deep link, a notification, a cold
//     start on the destination) the Hero has no partner and Flutter skips the
//     flight: the page arrives normally, with the correct final state.
//   • The destination hero is the page's own body, so nothing is duplicated and
//     the page's controls are live the moment it settles.
//   • Reduced motion bypasses the Hero entirely; the route transition already
//     detects `disableAnimations` and lands on the final state.
//
// The shuttle is a MATERIAL, not a screenshot: one rounded surface whose radius
// runs from a full circle to the page corner, whose colour runs from the
// bubble's raised surface to the page background, and which dissolves in the
// last beat so the real page resolves underneath/inside it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';

/// Stable, per-control transition identities. These strings are the contract
/// between a bubble and its destination: a bubble must never adopt another
/// bubble's identity, or the wrong sphere would appear to open.
abstract final class BubbleMorphTag {
  static const save = 'az-bubble-save';
  static const p2p = 'az-bubble-p2p';
  static const susu = 'az-bubble-susu';
  static const bills = 'az-bubble-bills';
}

/// Corner the destination surface settles at, matching the rising surfaces.
const double _pageRadius = 28;

/// The expanding material.
Widget _morphShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final colors = ProviderScope.containerOf(
    flightContext,
    listen: false,
  ).read(themeProvider).colors;
  final raised = colors.surface;
  final page = colors.background;

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      // Push runs 0 → 1; pop runs the same animation with the roles swapped, so
      // the surface always grows out of (or back into) the bubble.
      final t = direction == HeroFlightDirection.push
          ? Curves.easeOutCubic.transform(animation.value)
          : Curves.easeOutCubic.transform(1 - animation.value);

      return LayoutBuilder(
        builder: (context, constraints) {
          final shortest = constraints.biggest.shortestSide;
          final circle = shortest / 2;
          final radius = circle + (_pageRadius - circle) * t;

          // The material dissolves over the last fifth so the page's own
          // content resolves inside it rather than popping in behind a lid.
          final dissolve = t < 0.8
              ? 1.0
              : (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0);

          return Opacity(
            opacity: dissolve,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(raised, page, t),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: colors.textTertiary.withValues(alpha: 0.34 * (1 - t)),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// The bubble side of the flight. Wraps the REAL bubble so its geometry, press
/// behaviour and semantics are untouched.
class BubbleMorphSource extends StatelessWidget {
  const BubbleMorphSource({super.key, required this.tag, required this.child});

  final String tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return Hero(
      tag: tag,
      flightShuttleBuilder: _morphShuttle,
      // Keep the slot occupied at its own size while the flight is in the
      // overlay, so the row never reflows mid-transition.
      placeholderBuilder: (context, size, child) =>
          SizedBox(width: size.width, height: size.height),
      child: child,
    );
  }
}

/// The destination side. Put this around a screen's body; [tag] must match the
/// bubble that opens it. A page reached without a bubble simply has no partner
/// and arrives normally.
class BubbleMorphDestination extends ConsumerWidget {
  const BubbleMorphDestination({
    super.key,
    required this.tag,
    required this.child,
  });

  final String tag;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.of(context).disableAnimations) return child;
    // Material so the flight surface has a sane ancestor for text/ink while
    // the page body is the hero.
    return Hero(tag: tag, flightShuttleBuilder: _morphShuttle, child: child);
  }
}

/// A single flight at a time, per destination.
///
/// Two rapid taps on the same bubble used to race: the second push landed on
/// top of the first, and on a slow device the member ended up two pages deep.
/// This records the destination and refuses a duplicate within the window the
/// transition itself occupies.
abstract final class BubbleNavigation {
  static final Map<String, DateTime> _lastPush = <String, DateTime>{};

  static bool allow(
    String location, {
    // One transition's worth: long enough to swallow the second tap of a
    // double tap, short enough that a member who came back and tapped again is
    // never refused.
    Duration window = MotionTokens.standard,
  }) {
    final now = DateTime.now();
    final last = _lastPush[location];
    if (last != null && now.difference(last) < window) return false;
    _lastPush[location] = now;
    return true;
  }

  /// Test seam: forget every recorded push.
  static void reset() => _lastPush.clear();
}
