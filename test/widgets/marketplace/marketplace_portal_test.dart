import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/models/business_models.dart';

/// Marketplace ONE-SCREEN guards (correction H, 2026-10-04):
///   1. The bare marketplace tab is the ONE result screen — Eat / Shop /
///      Ride / Stay category controls with Near You as a peer control.
///   2. The portal machinery (world deck, "choose your world", resume card,
///      explore-all, back-to-portal bar) is GONE — no duplicated interaction
///      path exists.
///   3. Tapping a category IMMEDIATELY changes the result surface; tapping
///      the active category clears back to all results.
///   4. The "Featured picks near you" wording is gone.
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

void main() {
  testWidgets('the bare tab opens the ONE result screen', (tester) async {
    await _pumpHome(tester);

    // Exactly Eat / Shop / Ride / Stay + Near You on the control row.
    expect(find.text('Eat'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
    expect(find.byKey(const ValueKey('marketplace-near-you')),
        findsOneWidget);

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

    // The old category dial labels are gone.
    expect(find.text('Restaurants'), findsNothing);
    expect(find.text('Hotels'), findsNothing);
    expect(find.text('Transit'), findsNothing);
    expect(find.text('Retail'), findsNothing);
    expect(find.text('All'), findsNothing);
  });

  testWidgets('tapping Eat immediately changes the result surface',
      (tester) async {
    final notifier = await _pumpHome(tester);
    final baseline = notifier.searchedCategories.length;

    await tester.tap(find.text('Eat'));
    await tester.pump(const Duration(milliseconds: 400));

    // The category fires a real search through the existing plumbing —
    // no second screen, no portal hop.
    expect(notifier.searchedCategories.length, baseline + 1);
    expect(notifier.searchedCategories.last, 'FOOD_BEVERAGE');
    // The control shows its active state by key.
    expect(find.byKey(const ValueKey('marketplace-category-Eat')),
        findsOneWidget);

    // Tapping the active category clears back to all results.
    await tester.tap(find.text('Eat'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(notifier.searchedCategories.last, isNull);
  });

  testWidgets('the Featured picks wording is gone', (tester) async {
    await _pumpHome(tester);
    expect(find.text('Featured picks near you'), findsNothing);
    expect(find.textContaining('Featured picks'), findsNothing);
  });

  testWidgets('initialCategory still seeds the category filter',
      (tester) async {
    final notifier =
        await _pumpHome(tester, initialCategory: 'retail');
    // TASK-010b entry contract: the seeding search fires with the
    // normalised wire — unchanged by the one-screen correction.
    expect(notifier.searchedCategories.first, 'RETAIL');
    // Shop (RETAIL) renders as the active category control.
    expect(find.byKey(const ValueKey('marketplace-category-Shop')),
        findsOneWidget);
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
