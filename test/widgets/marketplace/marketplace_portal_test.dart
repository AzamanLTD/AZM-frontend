import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/models/business_models.dart';

/// Marketplace ONE-SCREEN guards (experience pass §11 + §12):
///   1. The bare marketplace tab is the ONE result screen — the category
///      SPEED DIAL (the radial-fan grammar) is THE category system, with
///      All as a real selectable state, and Near You as the ONLY control
///      outside the selector.
///   2. The portal machinery (world deck, "choose your world", resume card,
///      explore-all, back-to-portal bar) is GONE — no duplicated interaction
///      path exists.
///   3. Picking a category from the fan IMMEDIATELY changes the result
///      surface; picking All clears back to all results.
///   4. The star/featured surface is GONE — no "Featured picks near you",
///      no Featured wording, no star shortcut.
///   5. A launcher `initialCategory` still seeds the category filter
///      (TASK-010b entry contract, unchanged).

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

/// The dial anchor pill (the GestureDetector inside CategorySpeedDial)
/// — the ValueKey sits on the speed dial itself, whose slot spans the row.
Finder _dialAnchor() => find
    .descendant(
      of: find.byKey(const ValueKey('marketplace-category-dial')),
      matching: find.byType(GestureDetector),
    )
    .first;

void main() {
  testWidgets('the bare tab opens the ONE result screen', (tester) async {
    await _pumpHome(tester);

    // The category SPEED DIAL is the selector (§11): at rest the anchor
    // shows the current category — All, a REAL selectable state.
    expect(find.byKey(const ValueKey('marketplace-category-dial')),
        findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    // Near You is the ONLY additional control.
    expect(find.byKey(const ValueKey('marketplace-near-you')),
        findsOneWidget);
    // No flat row of standalone category buttons.
    for (final label in ['Eat', 'Shop', 'Ride', 'Stay']) {
      expect(find.byKey(ValueKey('marketplace-category-$label')),
          findsNothing);
    }

    // The portal machinery is GONE — every old duplicated interaction path.
    expect(find.text('Discover'), findsNothing);
    expect(find.text('Choose your world'), findsNothing);
    expect(find.byKey(const ValueKey('marketplace_explore_all')),
        findsNothing);
    expect(find.byKey(const ValueKey('marketplace_back_to_portal')),
        findsNothing);
    for (final wire in [
      'LOGISTICS',
      'FOOD_BEVERAGE',
      'HOSPITALITY',
      'RETAIL',
    ]) {
      expect(find.byKey(ValueKey('marketplace_world_$wire')), findsNothing);
    }

    // The old world-dial labels are gone (the fan's arms use the
    // four-word vertical language: Eat / Shop / Ride / Stay).
    expect(find.text('Restaurants'), findsNothing);
    expect(find.text('Hotels'), findsNothing);
    expect(find.text('Transit'), findsNothing);
    expect(find.text('Retail'), findsNothing);
  });

  testWidgets('picking Eat from the fan immediately changes the result '
      'surface; picking All clears back', (tester) async {
    final notifier = await _pumpHome(tester);
    final baseline = notifier.searchedCategories.length;

    // Open the radial fan, then pick the Eat satellite.
    await tester.tap(_dialAnchor());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eat'));
    await tester.pumpAndSettle();

    // The category fires a real search through the existing plumbing —
    // no second screen, no portal hop.
    expect(notifier.searchedCategories.length, baseline + 1);
    expect(notifier.searchedCategories.last, 'FOOD_BEVERAGE');
    // The dial anchor now announces Eat as the active category (the other
    // 'Eat' text is the legitimate discovery intent rail).
    expect(find.bySemanticsLabel(RegExp('Category: Eat')), findsOneWidget);

    // Picking All (a real selectable state) clears the filter.
    await tester.tap(_dialAnchor());
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(notifier.searchedCategories.last, isNull);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('the star/featured surface is gone entirely (§12)',
      (tester) async {
    await _pumpHome(tester);
    expect(find.text('Featured picks near you'), findsNothing);
    expect(find.textContaining('Featured'), findsNothing);
    // No star shortcut on the composition.
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('initialCategory still seeds the category filter',
      (tester) async {
    final notifier =
        await _pumpHome(tester, initialCategory: 'retail');
    // TASK-010b entry contract: the seeding search fires with the
    // normalised wire — unchanged by the one-screen correction.
    expect(notifier.searchedCategories.first, 'RETAIL');
    // The dial anchor renders Shop (RETAIL) as the active category.
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('results render on the one screen — no second marketplace '
      'screen before them', (tester) async {
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
    // The list/map area exists immediately on the bare tab.
    expect(find.byType(ListView), findsWidgets);
  });
}
