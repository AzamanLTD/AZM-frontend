// =============================================================================
// AZAMAN — BUSINESS RESULT CARD: story-ring suite (AZM-backend PR #371)
//
// Pins the authoritative storyState contract at the card layer:
//   • ring ONLY on hasActiveStory — a missing block (legacy payload /
//     backend without PR #371) renders NO ring
//   • unseen emphasis ONLY on a real `true` — semantic "New story" plus
//     the accent border
//   • hasUnseenStory == null (anonymous viewer) is NEVER treated as
//     unseen: quiet ring, no "New story" claim
//   • story availability is never inferred from logo/description/
//     review/follow fields — only the block draws the ring
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/widgets/marketplace/business_result_card.dart';

BusinessProduct _product() => BusinessProduct(
      id: 'jollof', businessProfileId: 'bp-1', name: 'Jollof Plate',
      slug: 'jollof-plate', priceUsdc: 12, totalRevenue: 0,
      imageUrls: const [], isActive: true, totalOrders: 5,
    );

BusinessProfile _business({BusinessStoryState? storyState}) =>
    BusinessProfile(
      id: 'bp-1', bizId: 'BIZ-1', businessName: 'Palm Court Kitchen',
      category: 'FOOD_BEVERAGE', description: 'Jollof, Legon',
      isVerified: true, isSuspended: false, kybStatus: 'VERIFIED',
      totalEscrows: 4, completedEscrows: 4, userId: 1, totalVolume: 100,
      averageRating: 4.7, username: 'palm-court', reviewCount: 12,
      products: [_product()], storyState: storyState,
    );

Future<void> _pumpCard(WidgetTester tester, BusinessProfile business) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (c, s) =>
                  Scaffold(body: BusinessResultCard(business: business, distanceKm: 2.4)),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

BoxDecoration? _ringDecoration(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('business-story-ring-BIZ-1'));
  if (finder.evaluate().isEmpty) return null;
  final decorated = tester.widget<DecoratedBox>(
    find
        .descendant(of: finder, matching: find.byType(DecoratedBox))
        .first,
  );
  return decorated.decoration as BoxDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('active + unseen → ring with unseen emphasis and "New story"',
      (tester) async {
    await _pumpCard(tester, _business(
      storyState: BusinessStoryState(
        hasActiveStory: true, hasUnseenStory: true,
        latestStoryAt: DateTime.parse('2026-10-25T10:00:00Z'),
      ),
    ));
    final deco = _ringDecoration(tester);
    expect(deco, isNotNull, reason: 'an active story draws a ring');
    expect(deco!.border!.top.width, 2.5, reason: 'unseen ring is the bold one');
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('New story')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('active + seen → quiet ring, no "New story" claim',
      (tester) async {
    await _pumpCard(tester, _business(
      storyState: BusinessStoryState(
        hasActiveStory: true, hasUnseenStory: false,
        latestStoryAt: DateTime.parse('2026-10-25T10:00:00Z'),
      ),
    ));
    final deco = _ringDecoration(tester);
    expect(deco, isNotNull);
    expect(deco!.border!.top.width, 2.0, reason: 'seen ring is the quiet one');
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp(r'\bStory\b')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('New story')), findsNothing);
    handle.dispose();
  });

  testWidgets('anonymous viewer (null unseen) is NOT treated as unseen',
      (tester) async {
    await _pumpCard(tester, _business(
      storyState: BusinessStoryState(
        hasActiveStory: true, hasUnseenStory: null,
        latestStoryAt: DateTime.parse('2026-10-25T10:00:00Z'),
      ),
    ));
    final deco = _ringDecoration(tester);
    expect(deco, isNotNull, reason: 'hasActiveStory is real without a token');
    expect(deco!.border!.top.width, 2.0, reason: 'null never gets unseen emphasis');
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('New story')), findsNothing,
        reason: 'the client must not claim new for an anonymous viewer');
    handle.dispose();
  });

  testWidgets('hasActiveStory false → NO ring', (tester) async {
    await _pumpCard(tester, _business(
      storyState: BusinessStoryState(
        hasActiveStory: false, hasUnseenStory: false, latestStoryAt: null,
      ),
    ));
    expect(_ringDecoration(tester), isNull);
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Story')), findsNothing);
    handle.dispose();
  });

  testWidgets('legacy payload without a storyState block → NO ring',
      (tester) async {
    await _pumpCard(tester, _business(storyState: null));
    expect(_ringDecoration(tester), isNull,
        reason: 'absence is honest — never a guessed ring');
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Story')), findsNothing);
    handle.dispose();
  });

  testWidgets('fromJson parses the wire block faithfully', (tester) async {
    final json = jsonDecode('''
      {"hasActiveStory": true, "hasUnseenStory": null,
       "latestStoryAt": "2026-10-25T10:00:00.000Z"}
    ''') as Map<String, dynamic>;
    final st = BusinessStoryState.fromJson(json);
    expect(st.hasActiveStory, true);
    expect(st.hasUnseenStory, isNull);
    expect(st.latestStoryAt, DateTime.parse('2026-10-25T10:00:00.000Z'));
  });
}
