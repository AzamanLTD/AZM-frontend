// =============================================================================
// PR #142 VISUAL PASS (2026-10-06) — category dial identity + control row.
//
// Laws pinned here:
//   • a selected REAL category (Eat/Shop/Ride/Stay) paints the anchor SOLID
//     in its OWN accent — never the generic gray/theme card (Eat's orange
//     identity survives selection)
//   • "All" stays the neutral base selector pill
//   • TYPOGRAPHY INVARIANCE: selecting a category changes only the state
//     colour/indicator — font, weight, spacing, family, size all stay put
//   • Near You sits at the FAR END of the control row, after a Spacer
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/widgets/liquid/category_speed_dial.dart';

const _eatAccent = Color(0xFFF59E0B);

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  final searchedCategories = <String?>[];

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    searchedCategories.add(category);
    // Recorded, not fired — no network in this guard.
  }
}

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: ThemeProvider.getThemeData(AzamanTheme.dark),
        home: Scaffold(body: Center(child: child)),
      ),
    );

Future<void> _pumpDial(
  WidgetTester tester, {
  String? selectedWire,
}) async {
  await tester.pumpWidget(
    _wrap(
      CategorySpeedDial(
        key: const ValueKey('marketplace-category-dial'),
        categories: const [
          CategoryDialItem(
              wire: null, icon: Icons.apps_rounded, label: 'All'),
          CategoryDialItem(
              wire: 'FOOD_BEVERAGE',
              icon: Icons.restaurant_rounded,
              label: 'Eat',
              accent: _eatAccent),
          CategoryDialItem(
              wire: 'RETAIL',
              icon: Icons.shopping_bag_rounded,
              label: 'Shop',
              accent: Color(0xFF00D97E)),
        ],
        selectedWire: selectedWire,
        colors: ThemeProvider.getColors(AzamanTheme.dark),
        onSelected: (_) {},
      ),
    ),
  );
  await tester.pump();
}

BoxDecoration _anchorDecoration(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .first,
  );
  final decoration = container.decoration!;
  return decoration as BoxDecoration;
}

Text _anchorText(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label));

void main() {
  testWidgets('All selected: the anchor stays the neutral theme-card pill',
      (tester) async {
    await _pumpDial(tester, selectedWire: null);
    final deco = _anchorDecoration(tester, 'All');
    final colors = ThemeProvider.getColors(AzamanTheme.dark);
    expect(deco.color, colors.card,
        reason: 'All is the only neutral/base selector');
    expect(_anchorText(tester, 'All').style!.color, colors.textPrimary);
  });

  testWidgets('Eat selected: the anchor PRESERVES its own category colour '
      '(no generic gray/theme card takeover)', (tester) async {
    await _pumpDial(tester, selectedWire: 'FOOD_BEVERAGE');
    final deco = _anchorDecoration(tester, 'Eat');
    expect(deco.color, _eatAccent,
        reason:
            'the selected anchor must stay in its category identity, not a '
            'generic gray/theme card');
    // The ink is the measured readable foreground for the accent.
    final ink = dialInk(_eatAccent, ThemeProvider.getColors(AzamanTheme.dark));
    expect(_anchorText(tester, 'Eat').style!.color, ink);
  });

  testWidgets('TYPOGRAPHY INVARIANCE: selection changes only state colour, '
      'never font/weight/spacing/family/size', (tester) async {
    await _pumpDial(tester, selectedWire: null);
    final allStyle = _anchorText(tester, 'All').style!;

    await _pumpDial(tester, selectedWire: 'FOOD_BEVERAGE');
    final eatStyle = _anchorText(tester, 'Eat').style!;

    expect(eatStyle.fontSize, allStyle.fontSize);
    expect(eatStyle.fontWeight, allStyle.fontWeight);
    expect(eatStyle.letterSpacing, allStyle.letterSpacing);
    expect(eatStyle.fontFamily, allStyle.fontFamily);
    expect(eatStyle.height, allStyle.height);
    expect(eatStyle.decoration, allStyle.decoration);
  });

  testWidgets('Near You sits at the FAR END of the control row, after the '
      'category dial and a Spacer — not hugging the fan', (tester) async {
    final notifier = _RecordingSearchNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: MarketplaceHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final dial = tester.getRect(
        find.byKey(const ValueKey('marketplace-category-dial')));
    final nearYou = tester.getRect(
        find.byKey(const ValueKey('marketplace-near-you')));

    // Near You is FAR right of the dial, at the end of the row.
    expect(nearYou.left, greaterThan(dial.right),
        reason: 'Near You must not sit next to the category pill');
    // It reads as the row's end utility: its right edge is within the
    // row's standard 16px horizontal inset of the screen edge.
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(nearYou.right, greaterThan(logicalWidth - 40),
        reason: 'Near You must reach the far end of the control row');
    // And the dial itself stays anchored left.
    expect(dial.left, lessThan(30));

    // A Spacer separates them: the row is NOT stretched to force it.
    final row = tester.widget<Row>(
      find
          .ancestor(
              of: find.byKey(const ValueKey('marketplace-category-dial')),
              matching: find.byType(Row))
          .first,
    );
    expect(row.children.whereType<Spacer>().length, 1);
  });
}
