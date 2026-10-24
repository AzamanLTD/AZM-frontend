import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/providers/business_provider.dart';
import 'package:azaman/screens/marketplace/marketplace_home_screen.dart';
import 'package:azaman/services/business_service.dart';
import 'package:azaman/services/nearby_location_resolver.dart';
import 'package:geolocator/geolocator.dart';

/// G2 — the Near You / Map CONTROL SPLIT. Near You and Map are separate
/// controls with separate state:
///   • the pill toggles the proximity FEED and never switches the view;
///   • the view segmented control switches the surface and never touches
///     the feed state;
///   • toggling Near You off returns to the normal search list WITHOUT a
///     re-fetch (the plain list kept its provider state the whole time);
///   • a failed location resolve is its own honest state — never "no
///     businesses", never a silent blank.

class _RecordingSearchNotifier extends BusinessSearchNotifier {
  _RecordingSearchNotifier() : super(BusinessService());

  int searchCalls = 0;

  @override
  Future<void> search(
    String query, {
    String? category,
    bool? verified,
    String? subcategory,
  }) async {
    searchCalls++;
    // Recorded, not fired — no network in this guard.
  }
}

class _FakeNearbyNotifier extends NearbySearchNotifier {
  _FakeNearbyNotifier() : super(BusinessService());

  int searchNearbyCalls = 0;
  int loadMoreCalls = 0;
  double? lastLat;
  double? lastLng;

  @override
  Future<void> searchNearby({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? category,
    String? q,
    bool? verified,
  }) async {
    searchNearbyCalls++;
    lastLat = lat;
    lastLng = lng;
    // Recorded, not fired — the test injects states directly.
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
  }

  void injectLocations(List<BusinessLocation> locations) {
    state = NearbySearchState(
      locations: locations,
      lat: 5.6,
      lng: -0.19,
      hasMore: true,
      nextPage: 1,
    );
  }

  void injectError(String message) {
    state = NearbySearchState(error: message, lat: 5.6, lng: -0.19);
  }
}

BusinessLocation _nearbyRow(String id, String name, {double? distanceKm}) =>
    BusinessLocation.fromJson({
      'id': id,
      'businessProfileId': 'bp-$id',
      'label': name,
      'address': 'Osu, Accra',
      'latitude': 5.56,
      'longitude': -0.19,
      'galleryUrls': <String>[],
      'isPrimary': true,
      'isActive': true,
      if (distanceKm != null) 'distanceKm': distanceKm,
      'businessProfile': {
        'id': 'bp-$id',
        'bizId': 'BIZ-$id',
        'businessName': name,
        'category': 'RETAIL',
        'logoUrl': null,
        'isVerified': true,
        'averageRating': 4.5,
        'totalEscrows': 10,
      },
    });

Position _position(double lat, double lng) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Resolver that SUCCEEDS — a device with location on.
class _SucceedingResolver extends NearbyLocationResolver {
  const _SucceedingResolver();

  @override
  Future<Position> resolve() async => _position(5.603, -0.187);
}

Future<(_RecordingSearchNotifier, _FakeNearbyNotifier)> _pumpHome(
  WidgetTester tester, {
  NearbyLocationResolver resolver =
      const FailingNearbyLocationResolver(),
}) async {
  final search = _RecordingSearchNotifier();
  final nearby = _FakeNearbyNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        businessSearchProvider.overrideWith((ref) => search),
        nearbySearchProvider.overrideWith((ref) => nearby),
      ],
      child: MaterialApp(
        home: MarketplaceHomeScreen(locationResolver: resolver),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  return (search, nearby);
}

void main() {
  testWidgets('Near You toggle does NOT switch the view mode', (tester) async {
    final (search, nearby) = await _pumpHome(tester);

    // Baseline: exactly the initState seeding search.
    expect(search.searchCalls, 1);

    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));

    // The pill fired a nearby resolve (no platform location in the test
    // environment → the resolve fails and sets _locationError, but the
    // FEED is now active).
    expect(nearby.searchNearbyCalls, 0,
        reason: 'no position in the test env — the resolve fails before '
            'any nearby search fires');
    // The VIEW never changed: the list seg is still the active surface —
    // the screen still renders the SEARCH list container, not a map
    // location prompt.
    expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
    expect(find.text('Find businesses near you'), findsNothing,
        reason: 'the pill must not open the map');
  });

  testWidgets('Near You ON renders the proximity rows from the nearby '
      'provider', (tester) async {
    final (search, nearby) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));

    nearby.injectLocations([
      _nearbyRow('near-1', 'Corner Kiosk', distanceKm: 0.2),
      _nearbyRow('near-2', 'Osu Mini Mart', distanceKm: 1.4),
    ]);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Corner Kiosk'), findsOneWidget);
    expect(find.text('Osu Mini Mart'), findsOneWidget);
    expect(find.text('200 m away'), findsOneWidget);
    expect(find.text('1.4 km away'), findsOneWidget);
    // Distance is the trailing fact — server-computed, client never
    // re-sorts.
    // Settle pump: the home screen owns pre-existing one-shot timers
    // longer than the interaction pumps (all near-you streams and
    // debounces are disposed/canceled — this is not a leak). Flush them
    // so the binding's pending-timer invariant holds at teardown.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('toggling Near You OFF restores the search list with NO '
      're-fetch', (tester) async {
    final (search, nearby) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));
    nearby.injectLocations([_nearbyRow('near-1', 'Corner Kiosk')]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Corner Kiosk'), findsOneWidget);

    // OFF — the normal list returns from its untouched provider state.
    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Corner Kiosk'), findsNothing,
        reason: 'the proximity feed is gone');
    // The initState search count is UNCHANGED — the plain list did not
    // re-fetch, its state was preserved the entire time.
    expect(search.searchCalls, 1,
        reason: 'toggling Near You off must not re-fire the search list');
    // Settle pump: the home screen owns pre-existing one-shot timers
    // longer than the interaction pumps (all near-you streams and
    // debounces are disposed/canceled — this is not a leak). Flush them
    // so the binding's pending-timer invariant holds at teardown.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('failed location resolve renders its OWN honest state — '
      'not "no businesses"', (tester) async {
    await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));

    // In the test environment there is no location platform, so the
    // resolve fails: the near-you list must show the LOCATION failure,
    // never the "no businesses nearby" empty state (the neighborhood was
    // never queried).
    expect(
      find.byKey(const Key('marketplace-nearby-location-error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('marketplace-nearby-empty')), findsNothing);
  });

  testWidgets('a RESOLVED position fires the nearby search with the real '
      'coordinates', (tester) async {
    final (search, nearby) =
        await _pumpHome(tester, resolver: const _SucceedingResolver());

    expect(nearby.searchNearbyCalls, 0);
    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));

    // The resolve SUCCEEDED → the feed fired from the real coordinates.
    expect(nearby.searchNearbyCalls, 1);
    expect(nearby.lastLat, 5.603);
    expect(nearby.lastLng, -0.187);
    // The search list is NOT re-fetched.
    expect(search.searchCalls, 1);
  });

  testWidgets('a nearby search failure renders the truthful failure state',
      (tester) async {
    final (search, nearby) = await _pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));
    nearby.injectError('SocketException');
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byKey(const Key('marketplace-nearby-failure')),
      findsOneWidget,
    );
    expect(find.text("Couldn't load nearby businesses"), findsOneWidget);
  });

  testWidgets('the view segmented control still switches to the map — '
      'independent of the pill', (tester) async {
    await _pumpHome(tester);

    // Near You ON first.
    await tester.tap(find.byKey(const ValueKey('marketplace-near-you')));
    await tester.pump(const Duration(milliseconds: 400));

    // Now switch to the map surface via the segmented control.
    await tester.tap(find.byIcon(Icons.location_on_outlined).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    // Without a platform position the map shows its location prompt —
    // the VIEW switched, without the pill having done it.
    expect(find.text('Find businesses near you'), findsOneWidget);

    // Back to list: the near-you feed state survives the view round-trip
    // (separate controls, separate state).
    await tester.tap(find.byIcon(Icons.view_agenda_outlined).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('marketplace-nearby-location-error')),
        findsOneWidget,
        reason: 'the proximity feed is still active after a map round-trip');
  });
}
