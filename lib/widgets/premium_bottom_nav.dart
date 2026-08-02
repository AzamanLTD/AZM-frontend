// =============================================================================
// AZAMAN — 5-Tab Adaptive Bottom Navigation with Per-Tab Badges
//
// Tabs: Home · Chat · P2P · Vault · Market
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

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}

const _kNavItems = [
  _NavItem(icon: HugeIconsStroke.home01, activeIcon: HugeIconsSolid.home01, label: 'Home'),
  _NavItem(icon: HugeIconsStroke.message01, activeIcon: HugeIconsSolid.message01, label: 'Chat'),
  _NavItem(icon: HugeIconsStroke.creditCard, activeIcon: HugeIconsSolid.creditCard, label: 'P2P'),
  _NavItem(icon: HugeIconsStroke.safeBox, activeIcon: HugeIconsSolid.safeBox, label: 'Vault'),
  _NavItem(icon: HugeIconsStroke.store01, activeIcon: HugeIconsSolid.store01, label: 'Market'),
];

class PremiumBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  const PremiumBottomNav({super.key, required this.selectedIndex, required this.onItemSelected});

  void _handleTap(int i) {
    if (i == selectedIndex) return;
    HapticFeedback.selectionClick();
    onItemSelected(i);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom > 0 ? bottom + 8 : 16),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(31),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.isDark ? 0.45 : 0.13),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: List.generate(
            _kNavItems.length,
            (i) => _NavButton(
              item: _kNavItems[i],
              isSelected: selectedIndex == i,
              index: i,
              colors: colors,
              onTap: () => _handleTap(i),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final int index;
  final AzamanColors colors;
  final VoidCallback onTap;
  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.index,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? colors.accent : colors.textTertiary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with scale bounce + cross-fade between outline/solid
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: isSelected ? 1.0 : 0.92),
              duration: reduceMotion ? Duration.zero : MotionTokens.fast,
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
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
        child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(anim), child: child),
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
          return _BadgeStack(icon: child!, count: c, showNumber: true, color: colors);
        },
        child: icon,
      );
    }

    // Tab 2 (P2P) — active trade count (dot indicator)
    if (index == 2) {
      return Consumer(
        builder: (_, ref, child) {
          final c = ref.watch(activeTradeCountProvider).value ?? 0;
          return _BadgeStack(icon: child!, count: c, showNumber: false, color: colors);
        },
        child: icon,
      );
    }

    // Tab 3 (Vault) — active vault goals count (dot indicator)
    if (index == 3) {
      return Consumer(
        builder: (_, ref, child) {
          // Vault badge: show dot if there are active vaults
          // Uses a simple provider check — replace with actual vault provider
          return child!;
        },
        child: icon,
      );
    }

    // Tab 4 (Market) — notification count for marketplace orders
    if (index == 4) {
      return Consumer(
        builder: (_, ref, child) {
          final c = ref.watch(unreadCountProvider);
          return _BadgeStack(icon: child!, count: c, showNumber: false, color: colors);
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
  const _BadgeStack({required this.icon, required this.count, required this.showNumber, required this.color});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (showNumber)
          Positioned(
            right: -6, top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
          )
        else
          Positioned(
            right: -2, top: -2,
            child: Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}
