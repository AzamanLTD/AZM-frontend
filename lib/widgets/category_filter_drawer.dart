// lib/widgets/category_filter_drawer.dart
// =============================================================================
// AZAMAN — CATEGORY FILTER DRAWER (Marketplace Redesign, 2026-07-04)
//
// Side drawer accessed via the tune/filter icon on the home screen.
// Shows all business categories as colorful chips. Primary categories (Transit,
// Restaurants, Hotels) appear as full-width rows with subtitles. Secondary
// categories appear as compact pills in a Wrap layout.
//
// Usage:
//   Scaffold(
//     endDrawer: CategoryFilterDrawer(
//       selectedCategory: _selectedCategory,
//       onSelected: (wire) { setState(() => _selectedCategory = wire); _fireSearch(); },
//     ),
//     ...
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/theme_provider.dart';

class CategoryFilterDrawer extends ConsumerWidget {
  final String? selectedCategory;
  final ValueChanged<String?> onSelected;

  const CategoryFilterDrawer({
    super.key,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;

    return Drawer(
      width: 300,
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Browse Categories',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: colors.textTertiary, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Select a category to filter businesses',
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
            ),
            Divider(height: 1, color: colors.divider),
            // ── Category list ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "All" chip — clears the filter
                    _primaryChip(
                      context: context,
                      colors: colors,
                      wire: null,
                      label: 'All Businesses',
                      icon: Icons.grid_view_rounded,
                      color: colors.accent,
                      selected: selectedCategory == null,
                    ),
                    const SizedBox(height: 24),

                    // Primary categories header
                    Text('PRIMARY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textTertiary,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 10),

                    // Transit, Restaurants, Hotels
                    ...BusinessCategories.primary.map((cat) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _primaryChip(
                            context: context,
                            colors: colors,
                            wire: cat.wire,
                            label: cat.label,
                            icon: cat.icon,
                            color: cat.color,
                            selected: selectedCategory == cat.wire,
                            subtitle: cat.subtitle,
                          ),
                        )),

                    const SizedBox(height: 24),

                    // Secondary categories header
                    Text('MORE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textTertiary,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 10),

                    // Secondary categories as compact pills
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: BusinessCategories.secondary
                          .map((cat) => _compactChip(
                                context: context,
                                wire: cat.wire,
                                label: cat.label,
                                icon: cat.icon,
                                color: cat.color,
                                selected: selectedCategory == cat.wire,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-width row chip for primary categories (with optional subtitle).
  Widget _primaryChip({
    required BuildContext context,
    required AzamanColors colors,
    required String? wire,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: () {
        onSelected(wire);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.09) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.22),
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? color : colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 11, color: colors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }

  /// Compact pill for secondary categories.
  Widget _compactChip({
    required BuildContext context,
    required String? wire,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () {
        onSelected(wire);
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? color.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.25),
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color:
                    selected ? color : color.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selected
                    ? color
                    : color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

