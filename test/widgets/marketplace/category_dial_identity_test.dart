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
//   • Near You sits at the FAR END of the control row, past the dial+Mix
//     cluster — separated by free row width (spaceBetween; a flex Spacer
//     is illegal inside the strip's horizontal scrollable), not hugging
//     the fan
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

Future<void> _pumpDial(WidgetTester tester, {String? selectedWire}) async {
  await tester.pumpWidget(
    _wrap(
      CategorySpeedDial(
        key: const ValueKey('marketplace-category-dial'),
        categories: const [
          CategoryDialItem(wire: null, icon: Icons.apps_rounded, label: 'All'),
          CategoryDialItem(
            wire: 'FOOD_BEVERAGE',
            icon: Icons.restaurant_rounded,
            label: 'Eat',
            accent: _eatAccent,
          ),
          CategoryDialItem(
            wire: 'RETAIL',
            icon: Icons.shopping_bag_rounded,
            label: 'Shop',
            accent: Color(0xFF00D97E),
          ),
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
    find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
  );
  final decoration = container.decoration!;
  return decoration as BoxDecoration;
}

Text _anchorText(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label));

void main() {
  testWidgets('All selected: the anchor stays the neutral theme-card pill', (
    tester,
  ) async {
    await _pumpDial(tester, selectedWire: null);
    final deco = _anchorDecoration(tester, 'All');
    final colors = ThemeProvider.getColors(AzamanTheme.dark);
    expect(
      deco.color,
      colors.card,
      reason: 'All is the only neutral/base selector',
    );
    expect(_anchorText(tester, 'All').style!.color, colors.textPrimary);
  });

  testWidgets('Eat selected: the anchor PRESERVES its own category colour '
      '(no generic gray/theme card takeover)', (tester) async {
    await _pumpDial(tester, selectedWire: 'FOOD_BEVERAGE');
    final deco = _anchorDecoration(tester, 'Eat');
    expect(
      deco.color,
      _eatAccent,
      reason:
          'the selected anchor must stay in its category identity, not a '
          'generic gray/theme card',
    );
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

  testWidgets('Near You sits at the FAR END of the control row, past the '
      'dial+Mix cluster — not hugging the fan', (tester) async {
    final notifier = _RecordingSearchNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(home: MarketplaceHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final dial = tester.getRect(
      find.byKey(const ValueKey('marketplace-category-dial')),
    );
    final nearYou = tester.getRect(
      find.byKey(const ValueKey('marketplace-near-you')),
    );

    // Near You is FAR right of the dial, at the end of the row.
    expect(
      nearYou.left,
      greaterThan(dial.right),
      reason: 'Near You must not sit next to the category pill',
    );
    // It reads as the row's end utility: its right edge is within the
    // row's standard 16px horizontal inset of the screen edge.
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      nearYou.right,
      greaterThan(logicalWidth - 40),
      reason: 'Near You must reach the far end of the control row',
    );
    // And the dial itself stays anchored left.
    expect(dial.left, lessThan(30));

    // The strip's control row separates the clusters with spaceBetween —
    // the same far-end grammar the Spacer used to deliver — because a flex
    // Spacer is illegal inside the horizontal scrollable the strip needs
    // on narrow phones (unbounded width). The dial+Mix cluster must sit
    // adjacent (same cluster, no stretch between them), with the free row
    // width falling between that cluster and Near You.
    final mixEntry = tester.getRect(
      find.byKey(const ValueKey('marketplace-mix-entry')),
    );
    expect(
      mixEntry.left,
      greaterThanOrEqualTo(dial.right),
      reason:
          'the Mix pill must sit in the dial\'s own cluster, not '
          'floating in the row\'s free space',
    );
    expect(
      nearYou.left,
      greaterThan(mixEntry.right + 8),
      reason:
          'the free row width must separate the dial+Mix cluster '
          'from Near You — Near You never hugs the cluster',
    );
    final controlRowFinder = find.ancestor(
      of: find.byKey(const ValueKey('marketplace-near-you')),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Row && w.mainAxisAlignment == MainAxisAlignment.spaceBetween,
      ),
    );
    expect(
      controlRowFinder,
      findsOneWidget,
      reason:
          'the control row must pin the clusters apart with '
          'spaceBetween — no flex Spacer inside the scrollable strip',
    );
    expect(controlRowFinder.evaluate().single.widget is Row, true);
  });

  // ── Workstream D selector pass (2026-10-21) ──────────────────────────────

  testWidgets('open fan: the selected category is announced EXACTLY ONCE '
      '— the goo ghost pill never duplicates the anchor semantics', (
    tester,
  ) async {
    final notifier = _RecordingSearchNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(home: MarketplaceHomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Open the fan.
    await tester.tap(find.byKey(const ValueKey('marketplace-category-dial')));
    await tester.pump(const Duration(milliseconds: 700));

    // Semantics assertions need an enabled, built semantics tree.
    final semanticsHandle = tester.ensureSemantics();
    await tester.pump();

    // Exactly ONE semantics node carries the anchor's utterance — the
    // ghost pill on the blob is excluded, so TalkBack never hears the
    // selected category twice (pre-fix the ghost duplicated a bare
    // 'All' node alongside the anchor).
    expect(find.bySemanticsLabel(RegExp('Category: All')), findsOneWidget);
    expect(
      find.bySemanticsLabel('All'),
      findsNothing,
      reason: 'the goo ghost is a visual echo, not a second node',
    );

    semanticsHandle.dispose();
  });
}
