// =============================================================================
// BUSINESS PROFILE SCREEN — REAL-ROUTE joystick Up test (PR #203 review
// round, item 7)
//
// The card-level and shell-level suites pin the joystick mechanics with
// counting delegates. This suite pins the LAST hop on the REAL screen:
// dragging UP on the storefront hero avatar and releasing must push the
// business's REAL catalog route (the CatalogStorefrontScreen built from
// the live menu contract) — and an honestly EMPTY catalog must fire
// nothing, with the dimmed satellite disclosing "No catalog yet".
//
// All data rides the DI seams this PR introduced: a fake BusinessService
// (profile + locations + invoices) and a fake ApiClient via
// apiClientProvider (follow-check, showcases, and the /business/:bizId
// menu fetch that decides hasCatalog). No global client, no network.
// =============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/screens/marketplace/business_profile_screen.dart';
import 'package:azaman/screens/marketplace/catalog_storefront_screen.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/widgets/marketplace/profile_joystick.dart';
import 'package:http/http.dart' as http;

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _MenuClient extends ApiClient {
  /// The live menu contract; [] means an honestly EMPTY catalog.
  final List<Map<String, dynamic>> uncategorisedProducts;

  _MenuClient({this.uncategorisedProducts = const []});

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers, bool requireAuth = true}) async {
    if (endpoint == '/business/BIZ-TEST01/menu') {
      return _json(200, {
        'success': true,
        'sections': const [],
        'uncategorisedProducts': uncategorisedProducts,
      });
    }
    if (endpoint.startsWith('/follows/check/')) {
      return _json(200, {'success': true, 'isFollowing': false});
    }
    if (endpoint.startsWith('/showcases/')) {
      return _json(200, {'success': true, 'items': const []});
    }
    return _json(404, {'success': false});
  }
}

class _ProfileService extends BusinessService {
  @override
  Future<BusinessProfile?> getBusinessByBizId(String bizId) async =>
      bizId == 'BIZ-TEST01' ? _business() : null;

  @override
  Future<List<BusinessLocation>> getPublicLocations(String bizId) async =>
      const [];

  @override
  Future<InvoicePage> getMyInvoices({
    String? status,
    int limit = 20,
    String? cursor,
  }) async =>
      (invoices: <BusinessInvoice>[], hasMore: false, nextCursor: null);
}

BusinessProfile _business() => BusinessProfile(
      id: 'biz-1',
      bizId: 'BIZ-TEST01',
      businessName: 'Makola Fresh Market',
      category: 'RETAIL',
      isVerified: true,
      isSuspended: false,
      kybStatus: 'VERIFIED',
      totalEscrows: 42,
      completedEscrows: 40,
      userId: 1,
      totalVolume: 1200,
      averageRating: 4.8,
      reviewCount: 24,
      username: 'makola',
      description: 'Genuine Accra goods.',
      address: '12 Kojo Thompson Rd, Accra',
      logoUrl: 'https://img.example/logo.png',
    );

Map<String, dynamic> _productJson(String name) => {
      'id': 'p-$name',
      'businessProfileId': 'biz-1',
      'name': name,
      'slug': name.toLowerCase(),
      'priceUsdc': 12,
      'totalRevenue': 0,
      'imageUrls': const [],
      'isActive': true,
      'totalOrders': 5,
    };

Future<void> _pumpScreen(
  WidgetTester tester, {
  _MenuClient? client,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
            client ?? _MenuClient(uncategorisedProducts: [_productJson('Kente Cloth')])),
      ],
      child: MaterialApp(
        home: BusinessProfileScreen(
          bizId: 'BIZ-TEST01',
          service: _ProfileService(),
        ),
      ),
    ),
  );
}

/// The screen's load is async and its discovery choreography is
/// timer-driven. The hero identity (and its joystick) is live only inside
/// the entrance beat — after the dip settles at the shopping snap the
/// identity is honestly faded out and pointer-ignored, so the drag must
/// happen in the SAME window the shell suite uses: small beats until the
/// shell attaches, one short beat inside the 180ms entrance beat, then
/// touch + drag + release. Never pumpAndSettle (the loading skeleton
/// shimmers with an infinite controller).
Future<void> _pumpToLiveHero(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(ProfileJoystick).evaluate().isNotEmpty) break;
  }
  expect(find.byType(ProfileJoystick), findsOneWidget,
      reason: 'the storefront hero attaches with its joystick');
  await tester.pump(const Duration(milliseconds: 50));
}

/// Settle AFTER a release: fixed beats through the sheet choreography and
/// the pushed route's 420ms transition (never pumpAndSettle — shimmer).
Future<void> _settle(WidgetTester tester) async {
  for (final ms in [200, 240, 260, 420, 150, 150, 100]) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('business profile screen — joystick up pushes the REAL catalog '
      'route', () {
    testWidgets('up + release on the hero avatar opens CatalogStorefrontScreen '
        'built from the live menu contract', (tester) async {
      await _pumpScreen(tester);
      await _pumpToLiveHero(tester);

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ProfileJoystick)));
      await tester.pump();
      // The dial claims the drag BEFORE the release (no long-press).
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(find.byType(CatalogStorefrontScreen), findsOneWidget,
          reason: 'Up releases onto the REAL catalog destination: the '
              'CatalogStorefrontScreen built from the fetched menu contract');
    });

    testWidgets('an honestly EMPTY catalog dims the menu satellite and a '
        'release fires nothing — no route is pushed', (tester) async {
      await _pumpScreen(tester, client: _MenuClient());
      await _pumpToLiveHero(tester);

      // Honest unavailability is disclosed on the satellite WHILE the
      // dial is held open.
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ProfileJoystick)));
      await tester.pump();
      expect(find.text('Products (No catalog yet)'), findsOneWidget);

      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(find.byType(CatalogStorefrontScreen), findsNothing,
          reason: 'a dead delegate never pushes a route');
    });
  });
}
