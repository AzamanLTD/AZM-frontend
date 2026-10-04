// =============================================================================
// AZAMAN — 3-Tab Adaptive Bottom Navigation with Per-Tab Badges
//
// Tabs: Home · Chat · Marketplace  (NEW-HOME §15: P2P is no longer a
// permanent primary destination — it lives behind the Home P2P module and
// its canonical routes.)
// Each tab shows a live badge (unread counts, active trades, vault goals, etc.)
// The nav is a floating glass pill that adapts to safe-area.
//
// TASK-010 — scroll-reactive compression. `main.dart` feeds every vertical
// scroll in the app into [navScrollCompression]; the pill shrinks 62→52, drops
// to 0.92 opacity and its labels collapse to icons-only over the first 60% of
// travel. At rest it is identical to the old nav. See F-026 for the deliberately
// preserved icon-scale convention.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/utils/azaman_haptics.dart';
import 'package:azaman/widgets/liquid/liquid_engine.dart';
import 'package:azaman/widgets/liquid_tab_backdrop.dart';
import 'package:azaman/theme/az_text.dart';

/// Scroll-reactive compression of the nav pill.
///
/// A single global [ValueNotifier] is written by the `NotificationListener` in
/// `main.dart` and read here, so the compression costs one rebuild of the
/// nav per scroll frame instead of threading a scroll controller through every
/// page. Value is the compression amount in [0,1] where 0 == full height and
/// 1 == fully compressed.
final ValueNotifier<double> navScrollCompression = ValueNotifier<double>(0);

/// Named compression constants so the curve is tunable in one place.
///
/// The compression is driven by the page's ABSOLUTE scroll offset, not by
/// per-frame deltas: the same pixel depth always produces the same pill state,
/// which makes the behaviour deterministic, bounded and reversible. The writer
/// side (`main.dart`, one `NotificationListener` over the whole shell) passes
/// every [ScrollNotification] to [applyTo]; nothing else may write to
/// [navScrollCompression].
class NavScrollCompression {
  const NavScrollCompression._();

  /// Scroll travel (logical pixels) from rest to fully compressed. ~1.5 list
  /// rows: enough that a deliberate scroll compresses the nav, short enough
  /// that it happens quickly and does not feel like the nav is chasing the
  /// finger.
  static const double travelPx = 90;

  /// Quantisation steps: the pill has 11 possible visual states between rest
  /// and compressed. Each step is ~1px of height and ~0.8% of opacity — visibly
  /// smooth — while capping a full-screen scroll at ~10 notifier writes
  /// instead of one per frame.
  static const int steps = 10;

  /// Fraction of compression at which the labels finish collapsing. Below
  /// this the labels are still legible; above it the pill is icon-only.
  static const double labelCollapseAt = 0.6;

  /// Opacity floor when fully compressed. A floating pill must never become
  /// translucent enough that the page shows through it, or it reads as a
  /// rendering bug rather than as depth.
  static const double compressedOpacity = 0.92;

  /// Height at rest (expanded pill).
  static const double expandedHeight = 62;

  /// Height when fully compressed.
  static const double collapsedHeight = 52;

  /// Lateral inset at rest.
  static const double expandedInset = 16;

  /// Lateral inset when fully compressed — the pill narrows as it shrinks.
  static const double collapsedInset = 34;

  /// Maps an absolute scroll offset onto the quantised compression value.
  ///
  /// Non-positive offsets (a page at rest, or the negative pixels of a
  /// pull-to-refresh overscroll) always produce 0 — the guard that keeps
  /// pull-to-refresh from compressing the nav.
  static double fromPixels(double pixels) {
    if (!pixels.isFinite || pixels <= 0) return 0;
    final raw = (pixels / travelPx).clamp(0.0, 1.0);
    return ((raw * steps).round() / steps).clamp(0.0, 1.0);
  }

  /// The TASK-010 writer: feed a scroll notification, get the notifier updated.
  ///
  /// Returns false so the notification keeps bubbling to any other listener.
  /// Horizontal scrollables (notably Home's balance rail) are ignored — they
  /// must never drive the vertical navigation chrome.
  static bool applyTo(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final next = fromPixels(n.metrics.pixels);
    if (next != navScrollCompression.value) {
      navScrollCompression.value = next;
    }
    return false;
  }
}

/// NEW-C — the per-tab scroll registry behind tap-active-tab scroll-to-top.
///
/// The shell has ONE `NotificationListener` above every page, so no page
/// needs a controller threaded through it. Each vertical scroll notification
/// is offered here, keyed by the CURRENT shell tab. Only the OUTERMOST
/// scrollable of a tab is recorded: a notification whose scrollable has a
/// `ScrollableState` ancestor is nested inside a bigger list (its scrolling
/// belongs to the outer list's contract) and is ignored. The most recently
/// scrolled outermost scrollable wins — the one the user perceives as "the
/// page".
class TabScrollRegistry {
  TabScrollRegistry._();

  /// The app-scoped registry the shell writes into. A singleton because the
  /// shell and the nav are the only writers/readers and both are app-scoped.
  static final TabScrollRegistry instance = TabScrollRegistry._();

  /// The tab → its outermost vertical scrollable. A [ScrollableState] (not
  /// a position) is stored so liveness is a plain `mounted` check — a
  /// position outlives inspection only while its scrollable is mounted.
  final Map<int, ScrollableState> _primary = {};

  /// Records [n] for [tab]. Returns false so the notification keeps bubbling
  /// to any other listener (the shell composes this with
  /// [NavScrollCompression.applyTo]).
  ///
  /// A notification's context sits INSIDE the scrollable that emitted it,
  /// so [Scrollable.maybeOf] from there resolves THAT scrollable. It is
  /// the tab's primary only when no vertical scrollable exists ABOVE it —
  /// nested lists defer to their outer list.
  bool record(int tab, ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final ctx = n.context;
    if (ctx == null) return false;
    final scrollable = Scrollable.maybeOf(ctx, axis: Axis.vertical);
    if (scrollable == null) return false;
    if (identical(_primary[tab], scrollable)) return false;
    if (Scrollable.maybeOf(scrollable.context, axis: Axis.vertical) != null) {
      return false; // nested — the outer list owns the tab's scroll-to-top
    }
    _primary[tab] = scrollable;
    return false;
  }

  /// The tab's outermost scrollable position, or null when it has none
  /// recorded or the recorded scrollable has been unmounted. Dead entries
  /// are dropped.
  ScrollPosition? primaryFor(int tab) {
    final state = _primary[tab];
    if (state == null) return null;
    if (!state.mounted) {
      _primary.remove(tab);
      return null;
    }
    // A mounted scrollable that has emitted a notification always has its
    // position built (the position exists before the first scroll event).
    return state.position;
  }

  /// Test-only: forget everything (the singleton survives across tests).
  @visibleForTesting
  void debugReset() => _primary.clear();
}

/// NEW-C — the tap-active-tab contract owner (§2.3):
///
///   * the tab page is scrolled  → spring its outermost scrollable to the
///     top with `kHouseSpring` (a haptic `selectionClick` confirms the tap)
///   * the page is already at the top → the subtle "already here" lift of
///     the whole content (scale 1.0 → 0.985 → 1.0) as the acknowledgement
///
/// Reduced motion: the spring becomes an instant jump and the lift does
/// not play — the information ("you are at the top") is unchanged.
///
/// The shell (MainWrapper) owns the instance, wires it into
/// [PremiumBottomNav.onActiveTabRetap] and scales its content by
/// [lift]. Living here as one production unit means the contract is the
/// same code in the app and in the regression tests.
class NavRetapController {
  NavRetapController({required TickerProvider vsync})
      : liftCtrl = AnimationController(
          vsync: vsync,
          duration: MotionTokens.control,
          value: 1.0,
        );

  final AnimationController liftCtrl;

  /// The lift: scale 1.0 → 0.985 (fast out) → 1.0 (settling ease). Subtle
  /// by design — it acknowledges the tap, it does not perform.
  static final Animatable<double> _liftTween = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.985)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.985, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 65,
    ),
  ]);

  /// The scale animation the shell applies to its content. Rests at 1.0.
  Animation<double> get lift => liftCtrl.drive(_liftTween);

  /// Handles a tap on the already-active tab.
  void handleRetap({
    required int tab,
    required TabScrollRegistry registry,
    required BuildContext context,
  }) {
    final position = registry.primaryFor(tab);
    if (position == null || position.pixels <= 0) {
      // Already at the top (or nothing scrollable): the lift is the whole
      // signal — no haptic, the motion itself confirms the tap.
      if (AzMotion.of(context).travel) liftCtrl.forward(from: 0);
      return;
    }
    AzamanHaptics.selection();
    if (AzMotion.of(context).travel) {
      position.animateTo(
        0,
        duration: MotionTokens.emphasized,
        curve: kHouseSpring,
      );
    } else {
      position.jumpTo(0);
    }
  }

  void dispose() => liftCtrl.dispose();
}

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

const _kNavItems = [
  _NavItem(
    icon: HugeIconsStroke.home01,
    activeIcon: HugeIconsSolid.home01,
    label: 'Home',
  ),
  _NavItem(
    icon: HugeIconsStroke.message01,
    activeIcon: HugeIconsSolid.message01,
    label: 'Chat',
  ),
  _NavItem(
    icon: HugeIconsStroke.store01,
    activeIcon: HugeIconsSolid.store01,
    label: 'Marketplace',
  ),
];

class PremiumBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  /// Long-press on a tab. Wired for TASK-010b (vertical launcher); optional so
  /// callers that do not implement it simply get the default press feedback.
  final ValueChanged<int>? onTabLongPress;

  /// NEW-C: a tap on the ALREADY-ACTIVE tab. When null the nav keeps its
  /// legacy acknowledgement (a haptic only); the shell supplies the real
  /// contract (scroll-to-top with `kHouseSpring` + the already-here lift)
  /// through [NavRetapController].
  final VoidCallback? onActiveTabRetap;

  /// NEW-HOME §8/§10 (audit): a control placed STRUCTURALLY BESIDE the
  /// nav — [navigation] [+] — not a FAB floating above it. The shell
  /// passes the + launcher trigger here; it shares the pill's band,
  /// vertical center and safe-area handling, so the layout stays stable
  /// across device sizes.
  final Widget? trailing;
  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.trailing,
    this.onTabLongPress,
    this.onActiveTabRetap,
  });

  void _handleTap(int i) {
    if (i == selectedIndex) {
      // NEW-C: a real retap contract (scroll-to-top + lift) when the caller
      // supplies one; the haptic-only acknowledgement remains only as the
      // default for callers that do not (F-025 is closed by the shell).
      final retap = onActiveTabRetap;
      if (retap != null) {
        retap();
        return;
      }
      AzamanHaptics.selection();
      return;
    }
    AzamanHaptics.nav();
    onItemSelected(i);
  }

  void _handleLongPress(int i) {
    final cb = onTabLongPress;
    if (cb == null) return;
    AzamanHaptics.selection();
    cb(i);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    // Passed down once so the buttons do not re-read MediaQuery in four
    // places, and so the whole nav agrees on the same mode in one frame.
    final reduceMotion = !AzMotion.of(context).travel;
    // One listen rebuilds the whole nav as the page scrolls.
    return ValueListenableBuilder<double>(
      valueListenable: navScrollCompression,
      builder: (context, raw, _) {
        // Reduced motion: no compression at all. The nav stays at rest height
        // and full opacity — the information is unchanged, nothing moves.
        final t = reduceMotion ? 0.0 : raw.clamp(0.0, 1.0);

        final h =
            NavScrollCompression.expandedHeight +
            (NavScrollCompression.collapsedHeight -
                    NavScrollCompression.expandedHeight) *
                t;
        final inset =
            NavScrollCompression.expandedInset +
            (NavScrollCompression.collapsedInset -
                    NavScrollCompression.expandedInset) *
                t;

        // The labels collapse over the first 60% of compression, so they are
        // gone well before the pill reaches its minimum height.
        final labelOpacity = (1.0 - (t / NavScrollCompression.labelCollapseAt))
            .clamp(0.0, 1.0);

        // NEW-HOME §10: the pill and any `trailing` control share ONE
        // bottom band. The trailing control sits in the row at the pill's
        // right, vertically centered on the pill, and the safe-area
        // padding below is computed ONCE for the whole band.
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottom > 0 ? bottom + AzSpace.sm : AzSpace.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: Opacity(
            // Never below `compressedOpacity` (0.92): the page must not show
            // through a floating pill, or it reads as a rendering bug.
            opacity:
                1.0 - ((1.0 - NavScrollCompression.compressedOpacity) * t),
            child: AnimatedContainer(
              duration: AzMotion.duration(context, MotionTokens.fast),
              height: h,
              decoration: BoxDecoration(
                // UX-CORRECTION §1 (dark nav separation): a #0A0A0A pill
                // on a #000000 page is one luma step apart — the nav read
                // as having vanished into the background. The pill now
                // sits on the CARD step of the dark elevation ramp
                // (#161616) and carries an explicit rim + a top highlight
                // so the floating surface is unmistakable even before
                // its shadow is seen. Light keeps its existing surface +
                // shadow treatment (the new #F2F3F5 page already gives
                // it strong separation).
                color: colors.isDark ? colors.card : colors.surface,
                // `pill` (999) self-clamps to half the height, so the shape
                // is a true pill at 62px and at 52px without tracking two radii.
                borderRadius: AzRadius.brPill,
                border: colors.isDark
                    ? Border.all(color: AzElevation.rimHighlight(true))
                    : null,
                // Subtle vertical highlight over the card step in dark:
                // BoxDecoration paints a gradient INSTEAD of its color, so
                // the ramp is baked into the gradient itself.
                gradient: colors.isDark
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(
                              Colors.white.withValues(alpha: 0.05),
                              colors.card),
                          colors.card,
                          Color.alphaBlend(
                              Colors.white.withValues(alpha: 0.02),
                              colors.card),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      )
                    : null,
                boxShadow: AzElevation.level3(colors.isDark),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final innerWidth = constraints.maxWidth;
                  return Stack(
                    children: [
                      LiquidTabBackdrop(
                        selectedIndex: selectedIndex,
                        tabCount: _kNavItems.length,
                        totalWidth: innerWidth,
                        // The backdrop must track the ANIMATED height, not the
                        // target: a 62px backdrop inside a gliding 52px pill
                        // would overflow. `constraints.maxHeight` inside this
                        // LayoutBuilder is the container's live height.
                        barHeight: constraints.maxHeight,
                        color: colors.accent,
                      ),
                      Row(
                        children: List.generate(
                          _kNavItems.length,
                          (i) => _NavButton(
                            item: _kNavItems[i],
                            isSelected: selectedIndex == i,
                            index: i,
                            colors: colors,
                            labelOpacity: labelOpacity,
                            reduceMotion: reduceMotion,
                            onTap: () => _handleTap(i),
                            onLongPress: onTabLongPress == null
                                ? null
                                : () => _handleLongPress(i),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
                  ),
                ),
              ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AzSpace.sm),
                trailing!,
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final int index;
  final AzamanColors colors;

  /// 1.0 = label fully visible, 0.0 = label fully collapsed.
  final double labelOpacity;

  /// Passed down so the nav does not re-read MediaQuery in four places.
  final bool reduceMotion;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.index,
    required this.colors,
    required this.labelOpacity,
    required this.reduceMotion,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? colors.accent : colors.textTertiary;

    // When the label is collapsing, the icon must stay optically centred in the
    // pill. The Column is centre-aligned, so shrinking the gap and the label
    // together keeps the icon centred without any manual offset.
    final showLabel = labelOpacity > 0.01;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with scale bounce + cross-fade between outline/solid.
            //
            // NOTE (pre-existing, kept deliberately — F-026): `end` is
            // `isSelected ? 1.0 : 0.92`, so the SELECTED icon is the full-size
            // one and unselected icons are scaled down. That is the opposite
            // of the usual convention, but it is the shipped behaviour and
            // changing it belongs to a task about the nav's identity, not to
            // scroll reactivity. `MotionTokens.spring` IS `Curves.easeOutBack`
            // — the curve this icon always used, now via the token.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: isSelected ? 1.0 : 0.92),
              duration: reduceMotion ? Duration.zero : MotionTokens.fast,
              curve: MotionTokens.spring,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: _badge(context, color),
            ),

            // The 4px gap and the label both collapse together.
            SizedBox(height: 4 * labelOpacity),

            if (showLabel)
              Opacity(
                opacity: labelOpacity,
                child: AnimatedDefaultTextStyle(
                  duration: reduceMotion ? Duration.zero : MotionTokens.fast,
                  curve: MotionTokens.enter,
                  // The scale's `caption` step is 10/w600/+0.3 — the nav used
                  // a bare 10px with -0.2 tracking before. Tracking now comes
                  // from the scale; only the weight still distinguishes
                  // selected from unselected, because the nav label is the one
                  // place where weight IS the hierarchy.
                  style: AzText.caption.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(item.label),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, Color color) {
    final reduceMotion = !AzMotion.of(context).travel;
    final icon = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : MotionTokens.fast,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: Icon(
        isSelected ? item.activeIcon : item.icon,
        color: color,
        size: 22,
        key: ValueKey(isSelected),
      ),
    );

    // Tab 1 (Chat) — unread message count
    if (index == 1) {
      return Consumer(
        builder: (_, ref, child) {
          final c = ref.watch(totalUnreadChatCountProvider).value ?? 0;
          return _BadgeStack(
            icon: child!,
            count: c,
            showNumber: true,
            color: colors,
          );
        },
        child: icon,
      );
    }

    // Tab 2 (Marketplace) — notification count for marketplace orders
    if (index == 2) {
      return Consumer(
        builder: (_, ref, child) {
          final c = ref.watch(unreadCountProvider);
          return _BadgeStack(
            icon: child!,
            count: c,
            showNumber: false,
            color: colors,
          );
        },
        child: icon,
      );
    }

    return icon;
  }
}

/// Reusable badge stack — shows a count badge or a dot
class _BadgeStack extends StatelessWidget {
  final Widget icon;
  final int count;
  final bool showNumber;
  final AzamanColors color;

  const _BadgeStack({
    required this.icon,
    required this.count,
    required this.showNumber,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (showNumber)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.danger,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: AzText.caption.copyWith(
                  // The badge sits on `danger`, so its text must be the paired
                  // foreground. `AzamanColors` does not carry an `onError`; the
                  // ColorScheme built from it does, and maps `onError` to white
                  // in both themes — the same value the old literal used, but
                  // now from the theme layer, so a future palette change
                  // cannot leave a white label on a light-red badge.
                  color: Theme.of(context).colorScheme.onError,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                  letterSpacing: 0,
                ),
              ),
            ),
          )
        else
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
