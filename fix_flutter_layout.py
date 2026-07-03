import os

home_file = '/Users/ghost/Downloads/AZM-frontend-main/lib/screens/marketplace/marketplace_home_screen.dart'
with open(home_file, 'r') as f:
    content = f.read()

# Fix ListTile error by wrapping in Material
content = content.replace('    return ListTile(', '    return Material(type: MaterialType.transparency, child: ListTile(')
content = content.replace('      onTap: () => onSelected(index),\n    );', '      onTap: () => onSelected(index),\n    ));')

with open(home_file, 'w') as f:
    f.write(content)

card_file = '/Users/ghost/Downloads/AZM-frontend-main/lib/widgets/business_card.dart'
with open(card_file, 'r') as f:
    content = f.read()

content = content.replace('height: 4,\n              color: _categoryColor ?? colors.accent,', 'height: 4, width: double.infinity,\n              color: _categoryColor ?? colors.accent,')

with open(card_file, 'w') as f:
    f.write(content)
