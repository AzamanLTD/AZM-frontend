import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';

/// Portal permanent guards (milestone 2026-09-30):
///   1. The bare marketplace tab is the PORTAL — a destination with an
///      identity header, a "choose your world" deck (one card per primary
///      category), the stories rail, featured picks, and an explore-all.
///   2. Picking a world enters explore mode with that category seeded.
///   3. "Explore all" enters explore mode unfiltered.
///   4. The back affordance returns to the portal surface of the SAME tab
///      instance and refreshes the unfiltered search.
///   5. A launcher `initialCategory` still lands directly in the
///      pre-filtered explore view (TASK-010b entry contract).

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  final List<String?> searchedCategories = [];

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

Future<_RecordingSearchNotifier> _pumpHome(
  WidgetTester tester, {
  String? initialCategory,
}) async {
  final notifier = _RecordingSearchNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [businessSearchProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        home: MarketplaceHomeScreen(initialCategory: initialCategory),
      ),
    ),
  );
  // Post-frame seeding search + one-shot child timers.
  await tester.pump(const Duration(milliseconds: 600));
  return notifier;
}


/// Scrolls the portal list until [finder] is built (ListView is lazy —
/// below-the-fold sections do not exist until scrolled into view).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('marketplace_portal_body')),
          matching: find.byType(Scrollable),
        )
        .first, // outermost = the portal vertical list itself
  );
}

void main() {
  testWidgets('bare tab opens on the portal destination', (tester) async {
    await _pumpHome(tester);

    expect(find.byKey(const ValueKey('marketplace_portal_body')), findsOneWidget);
    expect(find.text('Marketplace'), findsOneWidget);
    expect(find.text('Choose your world'), findsOneWidget);

    // One world card per primary category.
    for (final wire in ['LOGISTICS', 'FOOD_BEVERAGE', 'HOSPITALITY', 'RETAIL']) {
      expect(find.byKey(ValueKey('marketplace_world_$wire')), findsOneWidget);
    }

    await _reveal(tester, find.byKey(const ValueKey('marketplace_explore_all')));
    expect(find.byKey(const ValueKey('marketplace_explore_all')), findsOneWidget);
    // Explore machinery is NOT on the portal surface.
    expect(
        find.byKey(const ValueKey('marketplace_back_to_portal')), findsNothing);
  });

  testWidgets('tapping a world enters explore seeded with that category',
      (tester) async {
    final notifier = await _pumpHome(tester);
    notifier.searchedCategories.clear();

    await tester.tap(find.byKey(const ValueKey('marketplace_world_RETAIL')));
    await tester.pump(const Duration(milliseconds: 600));

    // Explore surface is up: back affordance visible, portal deck gone.
    expect(find.byKey(const ValueKey('marketplace_back_to_portal')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace_portal_body')), findsNothing);

    // The world tap fired a category-seeded search.
    expect(notifier.searchedCategories, ['RETAIL']);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('explore-all enters explore unfiltered', (tester) async {
    final notifier = await _pumpHome(tester);
    notifier.searchedCategories.clear();

    await _reveal(tester, find.byKey(const ValueKey('marketplace_explore_all')));
    await tester.tap(find.byKey(const ValueKey('marketplace_explore_all')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('marketplace_back_to_portal')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace_portal_body')), findsNothing);
    // Unfiltered: no additional category search is fired (the unfiltered
    // seed search from init still stands).
    expect(notifier.searchedCategories, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('back affordance returns to the portal and refreshes the unfiltered search',
      (tester) async {
    final notifier = await _pumpHome(tester);
    notifier.searchedCategories.clear();

    await tester.tap(find.byKey(const ValueKey('marketplace_world_LOGISTICS')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(notifier.searchedCategories, ['LOGISTICS']);

    await tester.tap(find.byKey(const ValueKey('marketplace_back_to_portal')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('marketplace_portal_body')), findsOneWidget);
    // The portal refreshes the unfiltered result set so world counts and
    // featured picks reflect the whole catalog.
    expect(notifier.searchedCategories, ['LOGISTICS', null]);
  });

  testWidgets('initialCategory still lands directly in explore', (tester) async {
    final notifier = await _pumpHome(tester, initialCategory: 'retail');

    expect(find.byKey(const ValueKey('marketplace_portal_body')), findsNothing);
    expect(find.byKey(const ValueKey('marketplace_back_to_portal')),
        findsOneWidget);
    expect(notifier.searchedCategories, ['RETAIL']);
  });
}
