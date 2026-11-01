// =============================================================================
// AZAMAN — STOREFRONT SHELL: social proof line (AZM-backend PR #372)
//
// Pins the profile presentation of friends/friends-of-friends counts:
//   • a successful response with a non-zero direct-friends anchor
//     renders the one-line label under the identity meta
//   • loading, error, and honest zeros render NOTHING — no spinner, no
//     "0 friends", no placeholder that reads like missing data
//   • the label only ever claims "Followed by" — a follow is NOT a
//     visit and the UI must never phrase it as one
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/server_social_proof_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/market_storefront_shell.dart';
import 'package:azaman/services/server_social_proof_service.dart';

BusinessProfile _business() => BusinessProfile(
  id: 'bp-1',
  bizId: 'BIZ-1',
  businessName: 'Makola Fresh Market',
  category: 'FOOD_BEVERAGE',
  description: 'Fresh produce',
  isVerified: true,
  isSuspended: false,
  kybStatus: 'VERIFIED',
  totalEscrows: 4,
  completedEscrows: 4,
  userId: 1,
  totalVolume: 100,
  averageRating: 4.7,
  username: 'makola',
  reviewCount: 12,
  products: const [],
);

Future<void> _pump(WidgetTester tester, ServerSocialProof? proof) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (proof != null)
          serverSocialProofProvider('bp-1').overrideWith((ref) async => proof),
      ],
      child: MaterialApp(
        home: MarketStorefrontShell(
          business: _business(),
          colors: ThemeProvider.getColors(AzamanTheme.light),
          bannerUrl: null,
          locations: const [],
          showcaseSlides: const [],
          isFollowing: false,
          unpaidInvoices: 0,
          hasCatalog: true,
          catalogLabel: 'Products',
          productsBuilder: (context) => [const Text('Product surface')],
        ),
      ),
    ),
  );
  // Run through the discovery choreography so the sheet settles.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump(const Duration(milliseconds: 420));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('real proof renders one honest line under the identity', (
    tester,
  ) async {
    await _pump(
      tester,
      const ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 2,
        friendsOfFriendsFollowingCount: 5,
      ),
    );
    expect(
      find.text('Followed by 2 friends · 5 friends of friends'),
      findsOneWidget,
    );
  });

  testWidgets('error/unavailable renders NOTHING — never "0 friends"', (
    tester,
  ) async {
    // No override: the real provider runs, has no backend in the test
    // environment, and must fail into honest absence.
    await _pump(tester, null);
    expect(find.textContaining('Followed by'), findsNothing);
    expect(find.textContaining('friends of friends'), findsNothing);
  });

  testWidgets('honest zero counts render NOTHING', (tester) async {
    await _pump(
      tester,
      const ServerSocialProof(
        businessProfileId: 'bp-1',
        friendsFollowingCount: 0,
        friendsOfFriendsFollowingCount: 0,
      ),
    );
    expect(find.textContaining('Followed by'), findsNothing);
  });
}
