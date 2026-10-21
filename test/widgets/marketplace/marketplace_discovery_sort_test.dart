// =============================================================================
// MARKETPLACE DISCOVERY — HONEST DEFAULT SORT widget tests.
//
// 2026-10-20 discovery refinement:
//   • the default ranking is Newest (createdAt) — a transparent,
//     data-grounded ordering the backend really sends
//   • the old default (topRated / averageRating) ranked the feed by a
//     signal the card surface no longer shows — silently dishonest
//   • the discovery listing shows NO star rating widgets
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';

/// Seeds results directly into the search state — no network.
class _SeededSearchNotifier extends BusinessSearchNotifier {
  _SeededSearchNotifier(List<BusinessProfile> results)
      : super(BusinessService()) {
    state = state.copyWith(results: results);
  }

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {}
}

BusinessProfile _biz(
  String id,
  String name,
  DateTime created, {
  double rating = 0,
  int escrows = 0,
}) =>
    BusinessProfile(
      id: id,
      bizId: id,
      businessName: name,
      category: 'RETAIL',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: escrows,
      completedEscrows: escrows,
      userId: 1,
      totalVolume: 0,
      averageRating: rating,
      username: 'biz-$id',
      createdAt: created,
    );

Future<void> _pumpHome(WidgetTester tester, List<BusinessProfile> results) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) =>
            _SeededSearchNotifier(results)),
      ],
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(480, 900)),
          child: Scaffold(body: MarketplaceHomeScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default feed order is Newest — not rating, not escrows',
      (tester) async {
    // 'Legendary' has the HIGHEST rating and most escrows; it is also the
    // OLDEST record. An honest Newest feed must rank it LAST.
    await _pumpHome(tester, [
      _biz('legend', 'Legendary Store',
          DateTime(2025, 1, 1), rating: 5.0, escrows: 999),
      _biz('fresh', 'Fresh Arrival', DateTime(2026, 10, 18), rating: 1.0),
      _biz('mid', 'Middle Biz', DateTime(2026, 6, 1), rating: 3.0),
    ]);

    // Read the rendered order of the business bars, top to bottom.
    final names = ['Legendary Store', 'Fresh Arrival', 'Middle Biz'];
    final positions = {
      for (final n in names) n: tester.getTopLeft(find.text(n)).dy,
    };
    final ordered = names.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));

    expect(ordered, [
      'Fresh Arrival', // newest first
      'Middle Biz',
      'Legendary Store', // oldest last, despite 5.0 rating + 999 escrows
    ]);
  });

  testWidgets('createdAt comes from the backend payload (fromJson)',
      (tester) async {
    final json = {
      'id': 'bp-x',
      'bizId': 'BIZ-X',
      'businessName': 'From API',
      'category': 'RETAIL',
      'isVerified': true,
      'isSuspended': false,
      'kybStatus': 'VERIFIED',
      'totalEscrows': 0,
      'completedEscrows': 0,
      'userId': 1,
      'totalVolume': 0,
      'averageRating': 0,
      'user': {'username': 'api-biz'},
      'createdAt': '2026-10-19T10:00:00.000Z',
    };
    final biz = BusinessProfile.fromJson(json);
    expect(biz.createdOrEpoch, DateTime.parse('2026-10-19T10:00:00.000Z'));
  });

  testWidgets('discovery cards show no star-rating widgets',
      (tester) async {
    await _pumpHome(tester, [
      _biz('legend', 'Legendary Store', DateTime(2025, 1, 1), rating: 4.8),
    ]);

    expect(find.text('4.8'), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });
}
