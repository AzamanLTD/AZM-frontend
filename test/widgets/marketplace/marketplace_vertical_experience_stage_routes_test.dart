import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/models/marketplace_booking_models.dart';
import 'package:azaman/providers/marketplace_booking_provider.dart';
import 'package:azaman/providers/theme_provider.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
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
  totalOrders: 0,
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
  products: [_product('Room 101')],
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

    await tester.tap(find.text('Continue to rooms'));
    expect(route, '/business-market/public-biz-123/hotel-booking');
  });

  testWidgets('transit preview keeps internal id for provider', (tester) async {
    await _pump(tester, business: _business('LOGISTICS'), onNavigate: (_) {});

    expect(find.text('No upcoming trips yet'), findsOneWidget);
    final widget = tester.widget<MarketplaceVerticalExperienceStage>(
      find.byType(MarketplaceVerticalExperienceStage),
    );
    expect(widget.business.id, 'internal-profile-1');
    expect(widget.business.bizId, 'public-biz-123');
  });

  testWidgets('transit "View trips" opens the trip list by the internal id', (
    tester,
  ) async {
    String? route;
    final business = _business('LOGISTICS');
    final trip = TransitTrip(
      id: 'trip-1',
      businessProfileId: business.id,
      vehicleId: 'v1',
      routeName: 'Circle - Madina',
      origin: 'Circle',
      destination: 'Madina',
      departureAt: DateTime(2026, 12, 1, 7, 30),
      fareUsdc: 0.6,
      availableSeats: 10,
      status: TripStatus.scheduled,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transitTripsProvider(business.id).overrideWith((ref) async => [trip]),
          seatAvailabilityProvider('trip-1').overrideWith(
            (ref) async => const SeatAvailability(
              tripId: 'trip-1',
              seats: [],
              availableCount: 0,
              totalSeats: 0,
              tripStatus: 'SCHEDULED',
              fareUsdc: 0.6,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarketplaceVerticalExperienceStage(
                business: business,
                colors: _colors,
                onNavigate: (value) => route = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('View trips'));
    expect(route, '/business-market/internal-profile-1/transit');
  });

  group("the store page's primary button", () {
    test('a hotel opens booking by its public bizId (the hotel API key)', () {
      expect(
        storePrimaryRoute(_business('HOSPITALITY')),
        '/business-market/public-biz-123/hotel-booking',
      );
    });

    test(
      'transit opens the trip list by the internal id (the trips filter)',
      () {
        expect(
          storePrimaryRoute(_business('LOGISTICS')),
          '/business-market/internal-profile-1/transit',
        );
      },
    );

    test(
      'real estate is not sent to the hotel flow (it refuses non-hotels)',
      () {
        expect(storePrimaryRoute(_business('REAL_ESTATE')), isNull);
        expect(storePrimaryRoute(_business('FOOD_BEVERAGE')), isNull);
      },
    );
  });
}
