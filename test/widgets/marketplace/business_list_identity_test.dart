// =============================================================================
// AZAMAN — WORKSTREAM G acceptance suite: business-list identity + avatar
// chrome (2026-10-25)
//
//   G1  declutter — the verified badge and the marketing description are
//       REMOVED from the list card; the identity line keeps only real
//       open-state, real distance and the category badge.
//   G2  the offering icon/tint mapping is the CENTRAL BusinessCategories
//       contract (no scattered per-widget maps that can drift).
//   G3  the primary-category badge sits at the 6 o'clock position of the
//       round profile avatar — centred on the avatar axis, bottom edge
//       flush with the circle bottom, cut-out moat, logo dominant.
//   G4  the bookmark INDICATOR sits top-right of the profile picture
//       (never the card body), reflects the real savedBusinessesProvider,
//       and reopening the action panel shows the accurate state.
//   G5  the panel offers 'Watch story' ONLY when the real stories
//       contract returns an unexpired story — never on empty/expired/
//       failed fetches, never with invented counts — and launches the
//       REAL story viewer.
// =============================================================================

import 'dart:convert';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:azaman/services/marketplace_booking_service.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';
import 'package:azaman/widgets/marketplace/business_result_card.dart';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Fake backend for the panel's REAL contracts: /follows/* and the
/// business stories route. Story payloads are injected per test.
class _RecordingClient extends ApiClient {
  final List<String> calls = [];
  Map<String, dynamic> storiesBody = const {'success': true, 'stories': []};
  bool bookmarked = false;

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add('GET $endpoint');
    // Canonical BusinessProfile.id drives the follow / show-less /
    // bookmark contracts; BIZ-1 remains a route parameter only.
    if (endpoint == '/follows/check/bp-1') {
      return _json(200, {'success': true, 'isFollowing': false});
    }
    if (endpoint == '/recommendation-feedback/check/bp-1') {
      return _json(200, {'success': true, 'applied': false});
    }
    if (endpoint.startsWith('/bookmarks')) {
      return _json(200, {
        'success': true,
        'total': bookmarked ? 1 : 0,
        'bookmarks': bookmarked
            ? [
                {
                  'businessProfileId': 'bp-1',
                  'businessName': 'Palm Court Kitchen',
                  'category': 'FOOD_BEVERAGE',
                  'savedAt': '2026-10-25T10:00:00.000Z',
                },
              ]
            : [],
      });
    }
    if (endpoint == '/marketplace/business/BIZ-1/stories') {
      return _json(200, storiesBody);
    }
    return _json(404, {'success': false});
  }

  @override
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    bool requireAuth = true,
    String? idempotencyKey,
  }) async {
    calls.add('POST $endpoint');
    if (endpoint == '/bookmarks') {
      bookmarked = true;
      return _json(201, {
        'success': true,
        'state': 'BOOKMARKED',
        'alreadyBookmarked': false,
        'bookmark': {
          'businessProfileId': 'bp-1',
          'savedAt': '2026-10-25T12:00:00.000Z',
        },
      });
    }
    return _json(404, {'success': false});
  }

  @override
  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add('DELETE $endpoint');
    if (endpoint == '/bookmarks/bp-1') {
      bookmarked = false;
      return _json(200, {
        'success': true,
        'state': 'NOT_BOOKMARKED',
        'removed': true,
      });
    }
    return _json(404, {'success': false});
  }
}

class _FailingStoriesClient extends _RecordingClient {
  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    if (endpoint == '/marketplace/business/BIZ-1/stories') {
      throw Exception('network down');
    }
    return super.get(endpoint, headers: headers, requireAuth: requireAuth);
  }
}

BusinessProduct _product(String name) => BusinessProduct(
  id: name.toLowerCase().replaceAll(' ', '-'),
  businessProfileId: 'bp-1',
  name: name,
  slug: name.toLowerCase().replaceAll(' ', '-'),
  priceUsdc: 12,
  totalRevenue: 0,
  imageUrls: const [],
  isActive: true,
  totalOrders: 5,
);

BusinessProfile _business({
  String category = 'FOOD_BEVERAGE',
  List<String> offeredCategories = const [],
  bool isVerified = true,
  String? description = 'Jollof and grilled tilapia, Legon',
}) => BusinessProfile(
  offeredCategories: offeredCategories,
  id: 'bp-1',
  bizId: 'BIZ-1',
  businessName: 'Palm Court Kitchen',
  category: category,
  description: description,
  isVerified: isVerified,
  isSuspended: false,
  kybStatus: 'VERIFIED',
  totalEscrows: 4,
  completedEscrows: 4,
  userId: 1,
  totalVolume: 100,
  averageRating: 4.7,
  username: 'palm-court',
  reviewCount: 12,
  products: [_product('Jollof Plate')],
);

Map<String, dynamic> _storyJson({required String id, required bool expired}) {
  final now = DateTime.now();
  final expires = expired
      ? now.subtract(const Duration(hours: 1))
      : now.add(const Duration(hours: 20));
  return {
    'id': id,
    'userId': '7',
    'businessProfileId': 'BIZ-1',
    'mediaUrl': 'https://cdn.example/s/$id.jpg',
    'caption': 'Fresh jollof tonight',
    'createdAt': now.toIso8601String(),
    'expiresAt': expires.toIso8601String(),
    'user': {'username': 'palm-court', 'profilePictureUrl': null},
  };
}

GoRouter _router(Widget home) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(body: home),
    ),
    GoRoute(
      path: '/business/:bizId',
      builder: (c, s) =>
          Scaffold(body: Text('biz-${s.pathParameters['bizId']}')),
    ),
  ],
);

Future<void> _pumpCard(
  WidgetTester tester,
  BusinessProfile business, {
  _RecordingClient? client,
}) async {
  SharedPreferences.setMockInitialValues({});
  final fake = client ?? _RecordingClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(fake),
        marketplaceBookingServiceProvider.overrideWithValue(
          MarketplaceBookingService(apiClient: fake),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: _router(BusinessResultCard(business: business)),
        theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
      ),
    ),
  );
  await tester.pump();
}

/// The avatar's action panel opens on press-and-hold now — the plain
/// tap belongs to the persistent liquid dial.
Future<void> _holdForPanel(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey('business-avatar-BIZ-1'))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('G1 — list-card declutter', () {
    testWidgets('the verified badge does NOT render on the list card '
        '(grounded identity line only)', (tester) async {
      await _pumpCard(tester, _business(isVerified: true));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.verified_rounded),
        findsNothing,
        reason: 'verified lives on the business surfaces, never the list',
      );
      expect(find.byIcon(Icons.verified_outlined), findsNothing);
    });

    testWidgets('the marketing description does NOT render as the list '
        'subtitle; the grounded inventory line does', (tester) async {
      await _pumpCard(tester, _business());

      expect(
        find.text('Jollof and grilled tilapia, Legon'),
        findsNothing,
        reason: 'the description is not the list subtitle (G1)',
      );
      // Grounded fallback for FOOD_BEVERAGE with 1 product.
      expect(find.text('1 item on the menu'), findsOneWidget);
    });

    testWidgets('unknown operating hours render NO open pill (honest '
        'absence), and distance renders only when supplied', (tester) async {
      // The fixture has no locations → OpenStatus.unknown → no pill.
      await _pumpCard(tester, _business());
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsNothing);
      expect(find.text('Closed'), findsNothing);
      expect(find.text('Closing soon'), findsNothing);
      expect(
        find.textContaining('km'),
        findsNothing,
        reason: 'no distance is invented when none is supplied',
      );
    });
  });

  group('G2 — central offering-icon contract', () {
    testWidgets('BusinessCategories.offeringIconFor is the single source '
        'the chips render from', (tester) async {
      await _pumpCard(
        tester,
        _business(
          category: 'HOSPITALITY',
          offeredCategories: const ['FOOD_BEVERAGE'],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(BusinessCategories.offeringIconFor('FOOD_BEVERAGE')),
        findsOneWidget,
        reason: 'the chip renders the CENTRAL map glyph',
      );
      expect(
        find.byIcon(BusinessCategories.offeringIconFor('HOSPITALITY')),
        findsNWidgets(2),
        reason: 'primary renders in badge + placeholder only',
      );
    });

    testWidgets('an unknown future wire value still renders the OTHER '
        'glyph — never a blank row', (tester) async {
      await _pumpCard(
        tester,
        _business(category: 'RETAIL', offeredCategories: const ['NANO_TECH']),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(BusinessCategories.offeringIconFor('NANO_TECH')),
        findsOneWidget,
      );
    });
  });

  group('G4 — bookmark indicator on the avatar', () {
    testWidgets('the indicator renders top-right of the profile picture '
        'ONLY when the business is saved', (tester) async {
      await _pumpCard(tester, _business());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('business-avatar-bookmark-BIZ-1')),
        findsNothing,
        reason: 'unsaved businesses show no indicator',
      );

      // Save through the REAL panel path, then reopen the card.
      await _holdForPanel(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('business-action-bookmark')));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      final indicator = find.byKey(
        const ValueKey('business-avatar-bookmark-BIZ-1'),
      );
      expect(
        indicator,
        findsOneWidget,
        reason: 'the provider state drives the indicator',
      );

      final avatar = tester.getRect(
        find.byKey(const ValueKey('business-avatar-BIZ-1')),
      );
      final ind = tester.getRect(indicator);
      // Top-right band of the profile picture.
      expect(ind.top <= avatar.top + 2, isTrue);
      expect(ind.right >= avatar.right - 2, isTrue);
      expect(ind.right <= avatar.right + 2, isTrue);
      expect(ind.center.dx > avatar.center.dx, isTrue);

      // It is NOT on the card body.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('business-card-body-BIZ-1')),
          matching: indicator,
        ),
        findsNothing,
      );
    });

    testWidgets('reopening the action panel shows the accurate saved '
        'state', (tester) async {
      await _pumpCard(tester, _business());

      await _holdForPanel(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('business-action-bookmark')));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        find.text('Remove bookmark'),
        findsOneWidget,
        reason: 'the row reflects the just-toggled real state',
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Reopen: still accurate.
      await _holdForPanel(tester);
      await tester.pumpAndSettle();
      expect(find.text('Remove bookmark'), findsOneWidget);
      expect(find.text('Bookmark'), findsNothing);
    });
  });

  group('G5 — Watch story (real contract only)', () {
    testWidgets('the panel offers Watch story ONLY when the real fetch '
        'returns an unexpired story', (tester) async {
      final client = _RecordingClient()
        ..storiesBody = {
          'success': true,
          'stories': [
            _storyJson(id: 's1', expired: false),
            _storyJson(id: 's2', expired: true),
          ],
        };
      await _pumpCard(tester, _business(), client: client);

      await _holdForPanel(tester);
      await tester.pumpAndSettle();

      expect(
        client.calls,
        contains('GET /marketplace/business/BIZ-1/stories'),
        reason: 'the panel verified the REAL stories contract',
      );
      expect(
        find.byKey(const ValueKey('business-action-watch-story')),
        findsOneWidget,
        reason: 'exactly one live story → the row renders',
      );
    });

    testWidgets('expired-only stories render NO Watch-story row (honest '
        'absence)', (tester) async {
      final client = _RecordingClient()
        ..storiesBody = {
          'success': true,
          'stories': [_storyJson(id: 's1', expired: true)],
        };
      await _pumpCard(tester, _business(), client: client);

      await _holdForPanel(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('business-action-watch-story')),
        findsNothing,
      );
      expect(find.text('Watch story'), findsNothing);
    });

    testWidgets('a failed stories fetch renders NO Watch-story row and '
        'breaks nothing else', (tester) async {
      await _pumpCard(tester, _business(), client: _FailingStoriesClient());

      await _holdForPanel(tester);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('business-action-watch-story')),
        findsNothing,
      );
      // The rest of the panel still works.
      expect(
        find.byKey(const ValueKey('business-action-follow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-action-bookmark')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-action-review')),
        findsOneWidget,
      );
    });

    testWidgets('no invented counts render anywhere in the panel', (
      tester,
    ) async {
      final client = _RecordingClient()
        ..storiesBody = {
          'success': true,
          'stories': [
            _storyJson(id: 's1', expired: false),
            _storyJson(id: 's2', expired: false),
          ],
        };
      await _pumpCard(tester, _business(), client: client);

      await _holdForPanel(tester);
      await tester.pumpAndSettle();

      expect(find.text('2 stories'), findsNothing);
      expect(find.text('2 new'), findsNothing);
      expect(find.text('Watch story'), findsOneWidget);
    });

    testWidgets('tapping Watch story launches the REAL story viewer with '
        'the fetched stories', (tester) async {
      final client = _RecordingClient()
        ..storiesBody = {
          'success': true,
          'stories': [_storyJson(id: 's1', expired: false)],
        };
      await _pumpCard(tester, _business(), client: client);

      await _holdForPanel(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('business-action-watch-story')),
      );
      // The viewer plays on a real timer — pumpAndSettle would advance
      // playback to completion and auto-dismiss the single-story group,
      // so pump fixed frames instead (route transition, then content).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.byType(StoryViewerScreen),
        findsOneWidget,
        reason: 'the REAL story viewer route is on top',
      );
      expect(
        find.text('biz-BIZ-1'),
        findsNothing,
        reason: 'the viewer opened — not the profile fallback',
      );
      expect(
        find.text('Fresh jollof tonight'),
        findsWidgets,
        reason: 'the REAL fetched caption renders in the viewer',
      );
    });
  });
}
