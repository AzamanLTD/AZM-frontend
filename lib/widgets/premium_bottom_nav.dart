// =============================================================================
// AZAMAN — 4-Tab Adaptive Bottom Navigation with Per-Tab Badges
//
// Tabs: Home · Chat · P2P · Market
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
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/theme/az_elevation.dart';
import 'package:azaman/theme/az_radius.dart';
import 'package:azaman/theme/az_space.dart';
import 'package:azaman/theme/motion_tokens.dart';
import 'package:azaman/theme/az_motion.dart';
import 'package:azaman/utils/azaman_haptics.dart';
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
    icon: HugeIconsStroke.creditCard,
    activeIcon: HugeIconsSolid.creditCard,
    label: 'P2P',
  ),
  _NavItem(
    icon: HugeIconsStroke.store01,
    activeIcon: HugeIconsSolid.store01,
    label: 'Market',
  ),
];

class PremiumBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  /// Long-press on a tab. Wired for TASK-010b (vertical launcher); optional so
  /// callers that do not implement it simply get the default press feedback.
  final ValueChanged<int>? onTabLongPress;
  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.onTabLongPress,
  });

  void _handleTap(int i) {
    if (i == selectedIndex) {
      // Re-tapping the active tab. The nav has no handle on the page's
      // ScrollController (pages own their own scrollables), so it cannot
      // scroll to top. What it CAN do is acknowledge the tap, which beats the
      // previous silent no-op. See F-025 for the scroll-to-top follow-up.
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

        return Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            0,
            inset,
            bottom > 0 ? bottom + AzSpace.sm : AzSpace.lg,
          ),
          child: Opacity(
            // Never below `compressedOpacity` (0.92): the page must not show
            // through a floating pill, or it reads as a rendering bug.
            opacity:
                1.0 - ((1.0 - NavScrollCompression.compressedOpacity) * t),
            child: AnimatedContainer(
              duration: AzMotion.duration(context, MotionTokens.fast),
              height: h,
              decoration: BoxDecoration(
                color: colors.surface,
                // `pill` (999) self-clamps to half the height, so the shape
                // is a true pill at 62px and at 52px without tracking two radii.
                borderRadius: AzRadius.brPill,
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

    // Tab 2 (P2P) — active trade count (dot indicator)
    if (index == 2) {
      return Consumer(
        builder: (_, ref, child) {
          final c = ref.watch(activeTradeCountProvider).value ?? 0;
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

    // Tab 3 (Market) — notification count for marketplace orders
    if (index == 3) {
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
