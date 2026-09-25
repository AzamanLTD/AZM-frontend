// =============================================================================
// FILTER CHIP BAR — Flutter V3 Marketplace Sprint (2026-06-21)
//
// Reusable horizontal scrollable filter chips. The selected chip uses the
// accent background with on-accent text; unselected chips use the card
// surface with secondary text. Fires AzamanHaptics.toggle() on tap.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/utils/azaman_haptics.dart';

class FilterChipBar extends ConsumerWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  const FilterChipBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final onAccent = colors.isDark ? Colors.black : Colors.white;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: _chip(
                label: labels[i],
                selected: i == selectedIndex,
                colors: colors,
                onAccent: onAccent,
                onTap: () {
                  if (i == selectedIndex) return;
                  AzamanHaptics.toggle();
                  onSelected(i);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required AzamanColors colors,
    required Color onAccent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colors.accent : colors.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? onAccent : colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
