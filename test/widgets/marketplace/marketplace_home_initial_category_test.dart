import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';

/// TASK-011 permanent guard: `MarketplaceHomeScreen(initialCategory:)` is the
/// TASK-010b entry contract. It must accept a wire, normalise it through the
/// launch allowlist, and establish the search's starting category — while a
/// null / unknown wire opens the marketplace unfiltered.

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
  // The seeding search fires from a post-frame callback in initState; give the
  // frame (and any one-shot child timers) time to elapse so no timer is left
  // pending at teardown.
  await tester.pump(const Duration(milliseconds: 600));
  return notifier;
}

void main() {
  testWidgets('initialCategory seeds the starting search category', (
    tester,
  ) async {
    final notifier = await _pumpHome(tester, initialCategory: 'retail');
    expect(notifier.searchedCategories, ['RETAIL']);
  });

  testWidgets('initialCategory accepts FOOD_BEVERAGE', (tester) async {
    final notifier = await _pumpHome(tester, initialCategory: 'FOOD_BEVERAGE');
    expect(notifier.searchedCategories, ['FOOD_BEVERAGE']);
  });

  testWidgets('initialCategory accepts LOGISTICS', (tester) async {
    final notifier = await _pumpHome(tester, initialCategory: 'LOGISTICS');
    expect(notifier.searchedCategories, ['LOGISTICS']);
  });

  testWidgets('initialCategory accepts HOSPITALITY', (tester) async {
    final notifier = await _pumpHome(tester, initialCategory: 'HOSPITALITY');
    expect(notifier.searchedCategories, ['HOSPITALITY']);
  });

  testWidgets('initialCategory accepts REAL_ESTATE', (tester) async {
    final notifier = await _pumpHome(tester, initialCategory: 'REAL_ESTATE');
    expect(notifier.searchedCategories, ['REAL_ESTATE']);
  });

  testWidgets('null initialCategory opens unfiltered', (tester) async {
    final notifier = await _pumpHome(tester);
    expect(notifier.searchedCategories, [null]);
  });

  testWidgets('an unknown wire opens unfiltered, never a guess', (
    tester,
  ) async {
    final notifier = await _pumpHome(tester, initialCategory: 'NOT_A_VERTICAL');
    expect(notifier.searchedCategories, [null]);
  });
}
