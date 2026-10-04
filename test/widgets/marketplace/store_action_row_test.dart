import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/saved_businesses_provider.dart';
import 'package:azaman/widgets/marketplace/store/store_action_row.dart';
import 'package:azaman/widgets/marketplace/store/store_identity_row.dart';

BusinessProfile _business() => const BusinessProfile(
      id: 'bp-1',
      bizId: 'BIZ-1',
      businessName: 'Mama Ama Kitchen',
      category: 'FOOD_BEVERAGE',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 0,
      completedEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: 4.8,
      username: 'mama-ama',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('primary action uses the vertical label; bookmark toggles saved state', (tester) async {
    var primary = 0;
    var share = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            StoreIdentityRow(business: _business()),
            StoreActionRow(
              business: _business(),
              onPrimary: () => primary++,
              onShare: () => share++,
              onToggleFollow: () {},
            ),
          ]),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Mama Ama Kitchen'), findsOneWidget);
    expect(find.byKey(const ValueKey('store_identity_context')), findsOneWidget);
    expect(find.byKey(const ValueKey('store_bookmark_off')), findsOneWidget);
    expect(find.byKey(const ValueKey('store_follow_off')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('store_primary_action')));
    await tester.tap(find.byKey(const ValueKey('store_share')));
    expect(primary, 1);
    expect(share, 1);

    await tester.tap(find.byKey(const ValueKey('store_bookmark_off')));
    await tester.pump();
    expect(container.read(savedBusinessesProvider).contains('BIZ-1'), isTrue);
    expect(find.byKey(const ValueKey('store_bookmark_on')), findsOneWidget);
  });
}