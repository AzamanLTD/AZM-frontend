// =============================================================================
// AZAMAN — 4-Tab Adaptive Bottom Navigation with Per-Tab Badges
//
// Tabs: Home · Chat · P2P · Market
// Each tab shows a live badge (unread counts, active trades, vault goals, etc.)
// The nav is a floating glass pill that adapts to safe-area.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/providers/chat_provider.dart';
import 'package:azaman/providers/trade_provider.dart';
import 'package:azaman/providers/notification_provider.dart';
import 'package:azaman/theme/motion_tokens.dart';
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
class NavScrollCompression {
  const NavScrollCompression._();

  /// Pixels of scroll travel needed to reach full compression.
  static const double travelPx = 72;

  /// Height at rest (expanded pill).
  static const double expandedHeight = 62;

  /// Height when fully compressed.
  static const double collapsedHeight = 52;

  /// Lateral inset at rest.
  static const double expandedInset = 16;

  /// Lateral inset when fully compressed — the pill narrows as it shrinks.
  static const double collapsedInset = 34;

  /// Radius at rest.
  static const double expandedRadius = 31;

  /// Radius when fully compressed.
  static const double collapsedRadius = 26;

  /// Maps a raw scroll delta onto a compression amount in [0,1].
  static double fromDelta(double delta) {
    if (travelPx <= 0) return delta > 0 ? 1 : 0;
    return (delta / travelPx).clamp(0.0, 1.0);
  }

  /// Eases the compression so the pill settles rather than tracking raw input.
  static double ease(double t) {
    final x = t.clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(x);
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
    if (i == selectedIndex) return;
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
    // One listen rebuilds the whole nav as the page scrolls.
    return ValueListenableBuilder<double>(
      valueListenable: navScrollCompression,
      builder: (context, raw, _) {
        final t = MediaQuery.disableAnimationsOf(context)
            ? 0.0
            : NavScrollCompression.ease(raw);
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
        final radius =
            NavScrollCompression.expandedRadius +
            (NavScrollCompression.collapsedRadius -
                    NavScrollCompression.expandedRadius) *
                t;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            0,
            inset,
            bottom > 0 ? bottom + 8 : 16,
          ),
          child: AnimatedContainer(
            duration: MotionTokens.fast,
            height: h,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: colors.isDark ? 0.45 : 0.13,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
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
                      barHeight: h,
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
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.index,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? colors.accent : colors.textTertiary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with scale bounce + cross-fade between outline/solid
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: isSelected ? 1.0 : 0.92),
              duration: reduceMotion ? Duration.zero : MotionTokens.fast,
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: _badge(context, color),
            ),
            const SizedBox(height: 4),
            // Label with smooth color + weight transition
            AnimatedDefaultTextStyle(
              duration: reduceMotion ? Duration.zero : MotionTokens.fast,
              curve: Curves.easeOut,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, Color color) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
                  color: Colors.white,
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
