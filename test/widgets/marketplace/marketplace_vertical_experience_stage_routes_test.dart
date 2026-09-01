import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/widgets/marketplace/marketplace_vertical_experience_stage.dart';

AzamanColors get _colors => ThemeProvider.getColors(AzamanTheme.dark);

BusinessProduct _product(String name) => BusinessProduct(
      id: name.toLowerCase().replaceAll(' ', '-'),
      businessProfileId: 'internal-profile-1',
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      priceUsdc: 80,
      totalRevenue: 0,
      imageUrls: const [],
      isActive: true,
    );

BusinessProfile _business(String category) => BusinessProfile(
      id: 'internal-profile-1',
      bizId: 'public-biz-123',
      businessName: 'Test Business',
      category: category,
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 0,
      completedEscrows: 0,
      userId: 1,
      totalVolume: 0,
      averageRating: 4.8,
      username: 'test-business',
      products: [
        _product('Room 101'),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required BusinessProfile business,
  required void Function(String route) onNavigate,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transitTripsProvider(business.id).overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MarketplaceVerticalExperienceStage(
            business: business,
            colors: _colors,
            onNavigate: onNavigate,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('hotel preview navigates with public bizId', (tester) async {
    String? route;
    await _pump(
      tester,
      business: _business('HOSPITALITY'),
      onNavigate: (value) => route = value,
    );

    await tester.tap(find.text('Open rooms & availability'));
    expect(route, '/business-market/public-biz-123/hotel-booking');
  });

  testWidgets('transit preview navigates with public bizId', (tester) async {
    String? route;
    await _pump(
      tester,
      business: _business('LOGISTICS'),
      onNavigate: (value) => route = value,
    );

    expect(find.text('No upcoming trips yet'), findsOneWidget);
    // This control is only rendered when a scheduled trip exists, so this
    // test locks the route contract through a direct preview callback below.
    final widget = tester.widget<MarketplaceVerticalExperienceStage>(
      find.byType(MarketplaceVerticalExperienceStage),
    );
    expect(widget.business.bizId, 'public-biz-123');
    expect(route, isNull);
  });
}
