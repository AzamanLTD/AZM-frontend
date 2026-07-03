import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:azaman/providers/theme_provider.dart';

class CategoryFilterPanel extends ConsumerWidget {
  final List<String> selectedCategories;
  final ValueChanged<List<String>> onApply;

  const CategoryFilterPanel({
    super.key,
    required this.selectedCategories,
    required this.onApply,
  });

  static const _primaryCategories = [
    {'value': 'FOOD_BEVERAGE', 'label': 'Restaurants', 'icon': Icons.restaurant, 'color': Color(0xFFF97316)},
    {'value': 'REAL_ESTATE', 'label': 'Hotels', 'icon': Icons.hotel, 'color': Color(0xFF8B5CF6)},
    {'value': 'LOGISTICS', 'label': 'Transit', 'icon': Icons.directions_bus, 'color': Color(0xFF3B82F6)},
  ];

  static const _secondaryCategories = [
    {'value': 'RETAIL', 'label': 'Retail', 'icon': Icons.shopping_bag, 'color': Color(0xFF10B981)},
    {'value': 'HEALTH_WELLNESS', 'label': 'Health', 'icon': Icons.local_hospital, 'color': Color(0xFFEF4444)},
    {'value': 'TECHNOLOGY', 'label': 'Technology', 'icon': Icons.computer, 'color': Color(0xFF6366F1)},
    {'value': 'ENTERTAINMENT', 'label': 'Entertainment', 'icon': Icons.movie, 'color': Color(0xFFEC4899)},
    {'value': 'EDUCATION', 'label': 'Education', 'icon': Icons.school, 'color': Color(0xFF14B8A6)},
    {'value': 'FINANCIAL_SERVICES', 'label': 'Finance', 'icon': Icons.account_balance, 'color': Color(0xFF64748B)},
    {'value': 'FREELANCE_SERVICES', 'label': 'Services', 'icon': Icons.handyman, 'color': Color(0xFFA855F7)},
    {'value': 'OTHER', 'label': 'Other', 'icon': Icons.category, 'color': Color(0xFF7B7B9A)},
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(themeProvider).colors;
    final selected = List<String>.from(selectedCategories);

    return Drawer(
      backgroundColor: colors.surface,
      width: MediaQuery.of(context).size.width * 0.82,
      child: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 20, right: 20, bottom: 16,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Text('Categories', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: colors.textPrimary,
                    )),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Primary categories
                    Text('Main', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: colors.textTertiary, letterSpacing: 1.2,
                    )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _primaryCategories.map((cat) {
                        final isSelected = selected.contains(cat['value']);
                        return _CategoryChip(
                          label: cat['label'] as String,
                          icon: cat['icon'] as IconData,
                          color: cat['color'] as Color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selected.remove(cat['value']);
                              } else {
                                selected.add(cat['value'] as String);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    // Secondary categories
                    Text('More', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: colors.textTertiary, letterSpacing: 1.2,
                    )),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _secondaryCategories.map((cat) {
                        final isSelected = selected.contains(cat['value']);
                        return _CategoryChip(
                          label: cat['label'] as String,
                          icon: cat['icon'] as IconData,
                          color: cat['color'] as Color,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                selected.remove(cat['value']);
                              } else {
                                selected.add(cat['value'] as String);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              // Apply button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
                ),
                child: SafeArea(
                  child: ElevatedButton(
                    onPressed: () {
                      onApply(selected);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Apply ${selected.isNotEmpty ? "(${selected.length})" : ""}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label, required this.icon, required this.color,
    required this.isSelected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? color : Colors.grey.shade700,
            )),
          ],
        ),
      ),
    );
  }
}
