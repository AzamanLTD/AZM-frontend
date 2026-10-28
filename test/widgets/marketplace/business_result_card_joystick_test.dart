// =============================================================================
// BUSINESS RESULT CARD — avatar joystick tests (Workstream A, 2026-10-26)
//
// Pins the CARD-level integration: the listing avatar rides the shared
// ProfileJoystick and every direction executes the REAL seam —
//   * up    -> the real catalog route, only when products exist,
//   * down  -> the real story viewer, only from a live stories fetch,
//   * right -> the durable bookmark POST keyed by the CANONICAL id,
//   * left  -> the MANDATORY show-less confirm — cancel makes zero
//              service calls, apply makes exactly one, Undo deletes,
//   * tap   -> the persistent icon-only liquid dial (labels live in
//              semantics — icon-only is a visual rule),
//   * hold  -> the full action panel (the joystick adds, never
//              replaces).
// All against the recording fake backend client from the parent suite.
// =============================================================================

import 'dart:convert';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:azaman/models/business_models.dart';
import 'package:azaman/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:azaman/widgets/marketplace/business_result_card.dart';
import 'package:azaman/widgets/stories/viewer/story_viewer_screen.dart';

const kCanonicalId = 'bp-1';

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _RecordingClient extends ApiClient {
  final List<String> calls = [];
  bool following = false;
  bool bookmarked = false;
  bool showLess = false;
  bool followCheckFails = false;
  bool showLessCheckFails = false;

  /// Live stories for the stories fetch — [] by default.
  List<Map<String, dynamic>> stories = [];

  @override
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    calls.add('GET $endpoint');
    if (endpoint == '/follows/check/$kCanonicalId' && !followCheckFails) {
      return _json(200, {'success': true, 'isFollowing': following});
    }
    if (endpoint == '/recommendation-feedback/check/$kCanonicalId') {
      if (showLessCheckFails) return _json(500, {'success': false});
      return _json(200, {'success': true, 'applied': showLess});
    }
    if (endpoint == '/bookmarks/check/$kCanonicalId') {
      return _json(200, {'success': true, 'bookmarked': bookmarked});
    }
    if (endpoint == '/marketplace/business/BIZ-1/stories') {
      return _json(200, {'success': true, 'stories': stories});
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
    calls.add('POST $endpoint ${body['businessProfileId'] ?? ''}');
    if (endpoint == '/follows') {
      following = true;
      return _json(201, {'success': true});
    }
    if (endpoint == '/recommendation-feedback') {
      showLess = true;
      return _json(201, {
        'success': true,
        'state': 'SHOW_LESS',
        'alreadyApplied': false,
        'appliedAt': '2026-10-26T11:00:00.000Z',
      });
    }
    if (endpoint == '/bookmarks') {
      bookmarked = true;
      return _json(201, {
        'success': true,
        'state': 'BOOKMARKED',
        'alreadyBookmarked': false,
        'bookmark': {
          'businessProfileId': kCanonicalId,
          'savedAt': '2026-10-26T12:00:00.000Z',
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
    if (endpoint == '/follows/$kCanonicalId') {
      following = false;
      return _json(200, {'success': true});
    }
    if (endpoint == '/recommendation-feedback/$kCanonicalId') {
      showLess = false;
      return _json(200, {'success': true, 'state': 'NONE', 'removed': true});
    }
    if (endpoint == '/bookmarks/$kCanonicalId') {
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

class _RouteRecorder extends NavigatorObserver {
  final routes = <String>[];
  @override
  void didPush(Route route, Route? previous) {
    final name = route.settings.name;
    if (name != null) routes.add(name);
    super.didPush(route, previous);
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
  List<BusinessProduct> products = const [],
  BusinessStoryState? storyState,
}) => BusinessProfile(
  id: 'bp-1',
  bizId: 'BIZ-1',
  businessName: 'Palm Court Kitchen',
  category: category,
  description: 'Jollof and grilled tilapia, Legon',
  isVerified: true,
  isSuspended: false,
  kybStatus: 'VERIFIED',
  totalEscrows: 4,
  completedEscrows: 4,
  userId: 1,
  totalVolume: 100,
  averageRating: 4.7,
  username: 'palm-court',
  reviewCount: 12,
  products: products,
  storyState: storyState,
);

Map<String, dynamic> _liveStoryJson() => {
  'id': 'st-1',
  'userId': '7',
  'businessProfileId': 'bp-1',
  'mediaUrl': 'https://img.example/story.png',
  'caption': 'Fresh today',
  'createdAt': DateTime.now()
      .subtract(const Duration(hours: 1))
      .toIso8601String(),
  'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
  'user': {
    'username': 'palm-court',
    'profilePictureUrl': 'https://img.example/avatar.png',
  },
};

GoRouter _router(NavigatorObserver obs, {Widget? home}) => GoRouter(
  initialLocation: '/',
  observers: [obs],
  routes: [
    GoRoute(
      path: '/',
      builder: (c, s) => Scaffold(body: home ?? const SizedBox.shrink()),
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
  ApiClient? client,
  NavigatorObserver? observer,
}) async {
  SharedPreferences.setMockInitialValues({});
  final obs = observer ?? _RouteRecorder();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (client != null) apiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp.router(
        routerConfig: _router(
          obs,
          home: BusinessResultCard(business: business, distanceKm: 2.4),
        ),
        theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
      ),
    ),
  );
  await tester.pump();
}

Future<TestGesture> _touchAvatar(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey('business-avatar-BIZ-1'))),
  );
  await tester.pump();
  return gesture;
}

Future<void> _moveAndRelease(
  WidgetTester tester,
  TestGesture gesture,
  Offset by,
) async {
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Key _sat(String name) => ValueKey('profile-dial-satellite-$name');

/// Opens the persistent dial with a plain tap on the card avatar.
Future<void> _openDial(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('business-avatar-BIZ-1')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('business result card — avatar joystick (Workstream A)', () {
    testWidgets('up + release pushes the real catalog route', (tester) async {
      final recorder = _RouteRecorder();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        observer: recorder,
      );

      final gesture = await _touchAvatar(tester);
      await _moveAndRelease(tester, gesture, const Offset(0, -22));

      expect(
        recorder.routes,
        contains('/business/:bizId'),
        reason:
            "GoRouter records the route PATTERN name; the resolved "
            'path parameter is asserted on the destination screen',
      );
      expect(
        find.text('biz-BIZ-1'),
        findsOneWidget,
        reason: 'the catalog route carries the real display bizId',
      );
    });

    testWidgets('up with NO products dims the satellite honestly and a '
        'release pushes nothing', (tester) async {
      final recorder = _RouteRecorder();
      await _pumpCard(
        tester,
        _business(products: const []),
        observer: recorder,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(0, -22));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        recorder.routes.where((r) => r != '/'),
        isEmpty,
        reason:
            'no dead delegate ever navigates (ignoring the '
            'initial / entry)',
      );

      // The honest disclosure lives on the PERSISTENT dial: icon-only
      // is a visual rule, labels are semantics.
      final semantics = tester.ensureSemantics();
      await _openDial(tester);
      expect(
        find.bySemanticsLabel('Menu (No catalog yet)'),
        findsOneWidget,
        reason: 'the dimmed satellite says exactly why it is dimmed',
      );
      await tester.tap(find.byKey(_sat('menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-dial')),
        findsOneWidget,
        reason: 'tapping a disabled icon keeps the dial open',
      );
      semantics.dispose();
    });

    testWidgets('down + release opens the real story viewer from a live '
        'stories fetch', (tester) async {
      final client = _RecordingClient()..stories = [_liveStoryJson()];
      await _pumpCard(
        tester,
        _business(
          products: [_product('Jollof Plate')],
          storyState: const BusinessStoryState(hasActiveStory: true),
        ),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(0, 22));
      await tester.pump();
      await gesture.up();
      // Bounded pumps: a full pumpAndSettle would let the viewer's
      // 5s story auto-advance timer consume the single story and pop
      // the route — the push itself must be verified before playback.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(StoryViewerScreen), findsOneWidget);
      expect(client.calls, contains('GET /marketplace/business/BIZ-1/stories'));
    });

    testWidgets('down with NO authoritative story state fires nothing '
        'and the satellite honestly says why', (tester) async {
      final client = _RecordingClient()..stories = [_liveStoryJson()];
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')], storyState: null),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(0, 22));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byType(StoryViewerScreen),
        findsNothing,
        reason: 'a guessed story must never open',
      );
      expect(
        client.calls.where((c) => c.contains('stories')),
        isEmpty,
        reason: 'no stories fetch without the authoritative state',
      );

      // The unavailable reason is disclosed on the persistent dial.
      final semantics = tester.ensureSemantics();
      await _openDial(tester);
      expect(
        find.bySemanticsLabel('Story (No active story)'),
        findsOneWidget,
        reason: 'the unavailable direction discloses its reason',
      );
      semantics.dispose();
    });

    testWidgets('down when the fetched stories are all EXPIRED opens '
        'nothing', (tester) async {
      final expired = _liveStoryJson();
      expired['expiresAt'] = DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final client = _RecordingClient()..stories = [expired];
      await _pumpCard(
        tester,
        _business(
          products: [_product('Jollof Plate')],
          storyState: const BusinessStoryState(hasActiveStory: true),
        ),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await _moveAndRelease(tester, gesture, const Offset(0, 22));

      expect(
        find.byType(StoryViewerScreen),
        findsNothing,
        reason: 'expired stories are an honest absence, not content',
      );
    });

    testWidgets('right + release posts the durable bookmark exactly once '
        'with the CANONICAL id', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await _moveAndRelease(tester, gesture, const Offset(22, 0));

      expect(
        client.calls.where((c) => c.startsWith('POST /bookmarks')).length,
        1,
        reason: 'the bookmark goes through the durable seam exactly once',
      );
      expect(
        client.calls,
        contains('POST /bookmarks $kCanonicalId'),
        reason:
            'keyed by the canonical BusinessProfile.id, not the '
            'display BIZ- code',
      );
    });

    testWidgets('left + release opens the mandatory confirm and CANCEL '
        'makes zero recommendation calls', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(-22, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('joystick-show-less-confirm')),
        findsOneWidget,
        reason: 'the release only OPENS the confirmation',
      );
      expect(
        client.calls.where((c) => c.contains('recommendation-feedback')).length,
        1,
        reason: 'only the state CHECK ran — no feedback was applied',
      );

      await tester.tap(find.byKey(const ValueKey('joystick-show-less-cancel')));
      await tester.pumpAndSettle();

      expect(
        client.calls.where((c) => c.startsWith('POST /recommendation')),
        isEmpty,
        reason: 'cancel leaves the recommendation contract untouched',
      );
      expect(
        find.byKey(const ValueKey('joystick-show-less-confirm')),
        findsNothing,
      );
    });

    testWidgets('left + release then CONFIRM applies show-less exactly '
        'once and closes', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(-22, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();

      expect(
        client.calls
            .where((c) => c.startsWith('POST /recommendation-feedback'))
            .length,
        1,
        reason: 'exactly one apply after an explicit confirm',
      );
      expect(
        find.byKey(const ValueKey('joystick-show-less-confirm')),
        findsNothing,
        reason: 'the dialog closes after applying',
      );
    });

    testWidgets('left when show-less is ALREADY applied offers Undo and '
        'the confirm deletes exactly once', (tester) async {
      final client = _RecordingClient()..showLess = true;
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await gesture.moveBy(const Offset(-22, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.text('Undo'),
        findsOneWidget,
        reason: 'the dialog reflects the real applied state',
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(
        client.calls
            .where((c) => c.startsWith('DELETE /recommendation-feedback'))
            .length,
        1,
        reason: 'undo removes the real SHOW_LESS state',
      );
      expect(client.showLess, false);
    });

    testWidgets('a plain tap opens the persistent icon-only dial — '
        'labels only in semantics, no visible action text', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      await _openDial(tester);

      expect(find.byKey(const ValueKey('profile-dial')), findsOneWidget);
      for (final name in ['menu', 'story', 'bookmark', 'showLess']) {
        expect(find.byKey(_sat(name)), findsOneWidget, reason: name);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('profile-dial')),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'icon-only is a visual rule',
      );
    });

    testWidgets('press-and-hold opens the full ACTION PANEL — the '
        'joystick adds, never replaces', (tester) async {
      final client = _RecordingClient();
      await _pumpCard(
        tester,
        _business(products: [_product('Jollof Plate')]),
        client: client,
      );

      final gesture = await _touchAvatar(tester);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 1));

      expect(
        find.byKey(const ValueKey('business-action-follow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('business-action-bookmark')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-dial')),
        findsNothing,
        reason: 'the hold never opens the dial',
      );

      // The same pointer's release fires nothing.
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('business-action-follow')),
        findsOneWidget,
        reason: 'the release neither closes the panel nor fires an action',
      );
    });
  });
}
