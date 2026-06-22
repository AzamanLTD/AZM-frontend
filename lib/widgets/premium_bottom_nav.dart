import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons_pro/hugeicons.dart';

import 'package:azaman/providers/theme_provider.dart';

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
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
    icon: HugeIconsStroke.piggyBank,
    activeIcon: HugeIconsSolid.piggyBank,
    label: 'Savings',
  ),
  // V3 Marketplace Sprint (2026-06-21): 5th tab — Premium Marketplace.
  _NavItem(
    icon: HugeIconsStroke.store01,
    activeIcon: HugeIconsSolid.store01,
    label: 'Market',
  ),
];

class PremiumBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  void _handleTap(int index) {
    if (index == selectedIndex) return;
    HapticFeedback.selectionClick();
    onItemSelected(index);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(
            color: colors.divider.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            top: 8,
            bottom: bottomInset > 0 ? 4 : 8,
          ),
          child: Row(
            children: List.generate(
              _kNavItems.length,
              (i) => _NavButton(
                item: _kNavItems[i],
                isSelected: selectedIndex == i,
                colors: colors,
                onTap: () => _handleTap(i),
              ),
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
  final AzamanColors colors;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? colors.accent : colors.textTertiary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: color,
                size: 23,
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
