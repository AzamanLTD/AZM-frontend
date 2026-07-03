import os

# 1. Fix business_card.dart (remove bad import)
card_file = '/Users/ghost/Downloads/AZM-frontend-main/lib/widgets/business_card.dart'
with open(card_file, 'r') as f:
    lines = f.readlines()

with open(card_file, 'w') as f:
    for line in lines:
        if 'package:azaman/models/business_categories.dart' not in line:
            f.write(line)

# 2. Append _CategoryBurgerSheet to marketplace_home_screen.dart and fix _resetAndLoad
home_file = '/Users/ghost/Downloads/AZM-frontend-main/lib/screens/marketplace/marketplace_home_screen.dart'
with open(home_file, 'r') as f:
    content = f.read()

content = content.replace('_resetAndLoad()', '_fireSearch()')

if '_CategoryBurgerSheet' not in content:
    burger_sheet = """
class _CategoryBurgerSheet extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final AzamanColors colors;

  const _CategoryBurgerSheet({
    required this.selectedIndex,
    required this.onSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text('Browse Categories',
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          _categoryTile(0, 'All Categories', Icons.grid_view_outlined, null),

          const SizedBox(height: 12),
          Text('PRIMARY', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            letterSpacing: 1.2,
          )),
          const SizedBox(height: 8),

          for (int i = 1; i <= 3; i++)
            _categoryTile(i,
              BusinessCategories.withAll[i].label,
              BusinessCategories.withAll[i].icon,
              BusinessCategories.withAll[i].color,
            ),

          const SizedBox(height: 12),
          Text('SECONDARY', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            letterSpacing: 1.2,
          )),
          const SizedBox(height: 8),

          for (int i = 4; i < BusinessCategories.withAll.length; i++)
            _categoryTile(i,
              BusinessCategories.withAll[i].label,
              BusinessCategories.withAll[i].icon,
              BusinessCategories.withAll[i].color,
            ),
        ],
      ),
    );
  }

  Widget _categoryTile(int index, String label, IconData icon, Color? color) {
    final selected = index == selectedIndex;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: (color ?? colors.divider).withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? colors.textSecondary, size: 20),
      ),
      title: Text(label, style: TextStyle(
        fontSize: 15,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? colors.accent : colors.textPrimary,
      )),
      trailing: selected
        ? Icon(Icons.check_circle, color: colors.accent, size: 20)
        : null,
      onTap: () => onSelected(index),
    );
  }
}
"""
    with open(home_file, 'a') as f:
        f.write("\n" + burger_sheet)

with open(home_file, 'w') as f:
    f.write(content)

with open(home_file, 'a') as f:
    if '_CategoryBurgerSheet' not in content:
        f.write("\n" + burger_sheet)
