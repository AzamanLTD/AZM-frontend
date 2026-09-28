import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';

/// TASK-011 permanent guard, part 2: the launch-wire NORMALISATION contract.
/// The full home-screen pump is memory-heavy, so these live in their own file
/// (each test file runs in its own tester process).

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
  testWidgets('initialCategory normalises case and surrounding whitespace', (
    tester,
  ) async {
    final notifier = await _pumpHome(tester, initialCategory: '  Hospitality ');
    expect(notifier.searchedCategories, ['HOSPITALITY']);
  });

  testWidgets('mixed-case launch wires still resolve to their wire', (
    tester,
  ) async {
    final notifier = await _pumpHome(tester, initialCategory: 'Real_Estate');
    expect(notifier.searchedCategories, ['REAL_ESTATE']);
  });

  testWidgets('an unknown value never maps to a nearby category', (
    tester,
  ) async {
    final notifier = await _pumpHome(tester, initialCategory: 'GROCERY');
    expect(notifier.searchedCategories, [null]);
  });
}
